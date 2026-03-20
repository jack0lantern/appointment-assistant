import { useNavigate, useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { LiveKitRoom } from '@livekit/components-react'
import api from '@/api/client'
import type { LiveSessionToken } from '@/types'
import SessionRoomContent from '@/components/session/SessionRoomContent'

export default function JoinLiveSession() {
  const { sessionId } = useParams<{ sessionId: string }>()
  const navigate = useNavigate()

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
          <p className="mt-2 text-sm text-slate-400">
            Make sure you're logged in and this session is for you.
          </p>
          <button
            onClick={() => navigate('/client/dashboard')}
            className="mt-4 text-sm text-blue-400 hover:underline"
          >
            Back to dashboard
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
      onDisconnected={() => navigate('/client/dashboard')}
    >
      <SessionRoomContent
        sessionId={Number(sessionId)}
        clientId={0}
        peerName={tokenData.peer_name ?? 'Therapist'}
        isTherapist={false}
      />
    </LiveKitRoom>
  )
}
