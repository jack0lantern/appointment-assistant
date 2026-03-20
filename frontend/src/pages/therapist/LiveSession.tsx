import { useState } from 'react'
import { useNavigate, useParams, useLocation } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { LiveKitRoom } from '@livekit/components-react'
import api from '@/api/client'
import type { LiveSessionToken } from '@/types'
import SessionRoomContent from '@/components/session/SessionRoomContent'

interface LocationState {
  clientId?: number
  clientName?: string
}

function ShareLink({ sessionId }: { sessionId: string }) {
  const [copied, setCopied] = useState(false)
  const shareUrl = `${window.location.origin}/client/session/${sessionId}/join`

  const handleCopy = async () => {
    await navigator.clipboard.writeText(shareUrl)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div className="flex items-center gap-2 rounded-lg bg-slate-800/80 px-3 py-2">
      <input
        readOnly
        value={shareUrl}
        className="flex-1 min-w-0 rounded bg-slate-900 px-2 py-1 text-xs text-slate-300"
      />
      <button
        type="button"
        onClick={handleCopy}
        className="shrink-0 rounded bg-slate-700 px-2 py-1 text-xs text-slate-200 hover:bg-slate-600"
      >
        {copied ? 'Copied!' : 'Copy link'}
      </button>
    </div>
  )
}

export default function LiveSession() {
  const { sessionId } = useParams<{ sessionId: string }>()
  const location = useLocation()
  const navigate = useNavigate()
  const state = (location.state as LocationState) ?? {}
  const clientId = state.clientId ?? 0
  const clientName = state.clientName ?? 'Client'

  const { data: tokenData, isLoading, error } = useQuery<LiveSessionToken>({
    queryKey: ['live-token', sessionId],
    queryFn: async () => {
      const { data } = await api.post(`/api/sessions/${sessionId}/live/token`)
      return data
    },
    enabled: !!sessionId,
    staleTime: Infinity,
  })

  if (isLoading) {
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950">
        <div className="text-slate-400">Connecting to session...</div>
      </div>
    )
  }

  if (error || !tokenData) {
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950">
        <div className="text-center">
          <p className="text-red-400">Failed to connect to session</p>
          <button
            onClick={() => navigate(-1)}
            className="mt-4 text-sm text-blue-400 hover:underline"
          >
            Go back
          </button>
        </div>
      </div>
    )
  }

  return (
    <LiveKitRoom
      serverUrl={tokenData.server_url}
      token={tokenData.token}
      connect={true}
      video={true}
      audio={true}
      onDisconnected={() => navigate(`/therapist/clients/${clientId}`)}
    >
      <div className="fixed left-4 top-16 z-[60] max-w-md">
        <p className="mb-1 text-xs text-slate-400">Share this link with your patient to join:</p>
        <ShareLink sessionId={sessionId ?? ''} />
      </div>
      <SessionRoomContent
        sessionId={Number(sessionId)}
        clientId={clientId}
        peerName={tokenData.peer_name ?? clientName}
        isTherapist={true}
      />
    </LiveKitRoom>
  )
}
