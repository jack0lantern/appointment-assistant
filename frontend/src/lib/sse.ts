const baseURL =
  import.meta.env.VITE_API_URL ??
  (import.meta.env.DEV ? 'http://localhost:8000' : '')

export interface SSEEvent {
  event: string
  data: string
}

export interface ConsumeSSEOptions {
  method?: 'GET' | 'POST'
  signal?: AbortSignal
  onEvent?: (event: SSEEvent) => void
  onError?: (err: Error) => void
}

/**
 * Consume a Server-Sent Events (SSE) stream from the backend.
 * Parses event: and data: lines and invokes onEvent for each message.
 */
export async function consumeSSE(
  path: string,
  options: ConsumeSSEOptions = {}
): Promise<void> {
  const { method = 'POST', signal, onEvent, onError } = options
  const url = path.startsWith('http') ? path : `${baseURL}${path}`
  const token = localStorage.getItem('token')

  const headers: Record<string, string> = {
    Accept: 'text/event-stream',
    'Content-Type': 'application/json',
  }
  if (token) {
    headers.Authorization = `Bearer ${token}`
  }

  let response: Response
  try {
    response = await fetch(url, {
      method,
      headers,
      signal,
    })
  } catch (fetchErr) {
    // #region agent log
    fetch(
      'http://127.0.0.1:7576/ingest/e725d10a-c411-49a0-8c32-614a03cd0fd3',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Debug-Session-Id': 'f30bcc' },
        body: JSON.stringify({
          sessionId: 'f30bcc',
          location: 'lib/sse.ts:fetch',
          message: 'SSE fetch failed (network error)',
          data: {
            url,
            path,
            baseURL,
            errMessage: fetchErr instanceof Error ? fetchErr.message : String(fetchErr),
          },
          timestamp: Date.now(),
        }),
      }
    ).catch(() => {})
    // #endregion
    throw fetchErr
  }

  if (!response.ok) {
    const err = new Error(`SSE request failed: ${response.status} ${response.statusText}`)
    onError?.(err)
    throw err
  }

  const reader = response.body?.getReader()
  if (!reader) {
    const err = new Error('No response body')
    onError?.(err)
    throw err
  }

  const decoder = new TextDecoder()
  let buffer = ''
  let currentEvent = ''
  let currentData = ''

  try {
    while (true) {
      const { done, value } = await reader.read()
      if (done) break

      buffer += decoder.decode(value, { stream: true })
      const lines = buffer.split('\n')
      buffer = lines.pop() ?? ''

      for (const line of lines) {
        if (line.startsWith('event:')) {
          currentEvent = line.slice(6).trim()
        } else if (line.startsWith('data:')) {
          currentData = line.slice(5).trim()
        } else if (line === '') {
          if (currentEvent || currentData) {
            onEvent?.({
              event: currentEvent || 'message',
              data: currentData,
            })
            currentEvent = ''
            currentData = ''
          }
        }
      }
    }

    if (currentEvent || currentData) {
      onEvent?.({
        event: currentEvent || 'message',
        data: currentData,
      })
    }
  } catch (err) {
    if (err instanceof Error && err.name === 'AbortError') {
      return
    }
    onError?.(err instanceof Error ? err : new Error(String(err)))
    throw err
  }
}
