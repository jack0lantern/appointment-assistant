import axios from 'axios'

// Dev: backend on localhost. Prod: same origin (backend serves frontend)
const baseURL =
  import.meta.env.VITE_API_URL ??
  (import.meta.env.DEV ? 'http://localhost:8000' : '')

// #region agent log
fetch('http://127.0.0.1:7576/ingest/e725d10a-c411-49a0-8c32-614a03cd0fd3', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'X-Debug-Session-Id': 'f30bcc' },
  body: JSON.stringify({
    sessionId: 'f30bcc',
    location: 'api/client.ts:init',
    message: 'API client initialized',
    data: { baseURL, viteApiUrl: import.meta.env.VITE_API_URL ?? '(unset)' },
    timestamp: Date.now(),
  }),
}).catch(() => {})
// #endregion

const api = axios.create({ baseURL })

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token')
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

api.interceptors.response.use(
  (response) => response,
  (error) => {
    // #region agent log
    const fullUrl = error.config?.baseURL && error.config?.url
      ? `${error.config.baseURL}${error.config.url}`
      : (error.config?.url ?? 'unknown')
    fetch('http://127.0.0.1:7576/ingest/e725d10a-c411-49a0-8c32-614a03cd0fd3', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Debug-Session-Id': 'f30bcc' },
      body: JSON.stringify({
        sessionId: 'f30bcc',
        location: 'api/client.ts:response-interceptor',
        message: 'API request failed',
        data: {
          method: error.config?.method,
          url: fullUrl,
          baseURL: error.config?.baseURL,
          status: error.response?.status,
          errMessage: error.message,
          isNetworkError: !error.response,
        },
        timestamp: Date.now(),
      }),
    }).catch(() => {})
    // #endregion
    if (error.response?.status === 401) {
      localStorage.removeItem('token')
      localStorage.removeItem('user')
      window.location.href = '/login'
    }
    return Promise.reject(error)
  }
)

export default api
