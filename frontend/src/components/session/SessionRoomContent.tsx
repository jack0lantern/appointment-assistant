import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useMutation, useQuery } from '@tanstack/react-query'
import {
  VideoTrack,
  useTracks,
  RoomAudioRenderer,
} from '@livekit/components-react'
import { Track } from 'livekit-client'
import api from '@/api/client'
import type { RecordingStatus } from '@/types'
import SessionControls from '@/components/session/SessionControls'
import ConsentModal from '@/components/session/ConsentModal'
import RecordingIndicator from '@/components/session/RecordingIndicator'

function SessionTimer({ startTime }: { startTime: number }) {
  const [elapsed, setElapsed] = useState(0)
  useEffect(() => {
    const interval = setInterval(() => {
      setElapsed(Math.floor((Date.now() - startTime) / 1000))
    }, 1000)
    return () => clearInterval(interval)
  }, [startTime])

  const mins = Math.floor(elapsed / 60)
  const secs = elapsed % 60
  return (
    <span className="tabular-nums">
      {String(mins).padStart(2, '0')}:{String(secs).padStart(2, '0')}
    </span>
  )
}

function VideoGrid() {
  const tracks = useTracks(
    [
      { source: Track.Source.Camera, withPlaceholder: true },
    ],
    { onlySubscribed: false },
  )

  return (
    <div className="grid h-full grid-cols-1 gap-2 p-2 md:grid-cols-2">
      {tracks.map((trackRef) => (
        <div
          key={trackRef.participant.sid}
          className="relative overflow-hidden rounded-xl bg-slate-800"
        >
          {trackRef.publication?.track ? (
            <VideoTrack
              trackRef={trackRef}
              className="h-full w-full object-cover"
            />
          ) : (
            <div className="flex h-full min-h-[240px] items-center justify-center">
              <div className="flex h-20 w-20 items-center justify-center rounded-full bg-slate-700 text-2xl font-semibold text-white">
                {trackRef.participant.name?.charAt(0)?.toUpperCase() ?? '?'}
              </div>
            </div>
          )}
          <div className="absolute bottom-2 left-2 rounded bg-black/60 px-2 py-0.5 text-xs text-white">
            {trackRef.participant.name ?? trackRef.participant.identity}
            {trackRef.participant.isLocal && ' (You)'}
          </div>
        </div>
      ))}
    </div>
  )
}

interface SessionRoomContentProps {
  sessionId: number
  clientId: number
  peerName: string
  isTherapist: boolean
}

export default function SessionRoomContent({
  sessionId,
  clientId,
  peerName,
  isTherapist,
}: SessionRoomContentProps) {
  const navigate = useNavigate()
  const [showConsentModal, setShowConsentModal] = useState(false)
  const [startTime] = useState(Date.now())

  const { data: recordingStatus, refetch: refetchRecording } = useQuery<RecordingStatus>({
    queryKey: ['recording-status', sessionId],
    queryFn: async () => {
      const { data } = await api.get(`/api/sessions/${sessionId}/recording/status`)
      return data
    },
    refetchInterval: 3000,
  })

  const isRecording = recordingStatus?.recording_status === 'recording'
  const allConsented = recordingStatus?.all_consented ?? false

  const submitConsent = useMutation({
    mutationFn: async (consented: boolean) => {
      await api.post(`/api/sessions/${sessionId}/recording/consent`, { consented })
    },
    onSuccess: () => refetchRecording(),
  })

  const startRecording = useMutation({
    mutationFn: async () => {
      await api.post(`/api/sessions/${sessionId}/recording/start`)
    },
    onSuccess: () => refetchRecording(),
  })

  const stopRecording = useMutation({
    mutationFn: async () => {
      await api.post(`/api/sessions/${sessionId}/recording/stop`)
    },
    onSuccess: () => refetchRecording(),
  })

  const endSession = useMutation({
    mutationFn: async () => {
      await api.post(`/api/sessions/${sessionId}/live/end`)
    },
    onSuccess: () => {
      if (isTherapist) {
        if (recordingStatus?.recording_status && recordingStatus.recording_status !== null) {
          navigate(`/therapist/session/${sessionId}/review`, {
            state: { clientId, clientName: peerName },
          })
        } else {
          navigate(`/therapist/clients/${clientId}`)
        }
      }
    },
  })

  const handleToggleRecording = useCallback(() => {
    if (isRecording) {
      stopRecording.mutate()
    } else if (allConsented) {
      startRecording.mutate()
    } else {
      setShowConsentModal(true)
    }
  }, [isRecording, allConsented, startRecording, stopRecording])

  const handleConsentAccept = useCallback(() => {
    submitConsent.mutate(true)
    setShowConsentModal(false)
  }, [submitConsent])

  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-slate-950">
      <div className="flex items-center justify-between border-b border-slate-800 px-4 py-2">
        <div className="text-sm text-slate-300">
          Session with <span className="font-medium text-white">{peerName}</span>
        </div>
        <div className="flex items-center gap-4 text-sm text-slate-400">
          <SessionTimer startTime={startTime} />
        </div>
      </div>

      <RecordingIndicator isRecording={isRecording} />

      <div className="flex-1 overflow-hidden">
        <VideoGrid />
      </div>

      <RoomAudioRenderer />

      <div className="border-t border-slate-800 p-4">
        <SessionControls
          isRecording={isRecording}
          canRecord={allConsented}
          onToggleRecording={handleToggleRecording}
          onEndSession={() => endSession.mutate()}
          isTherapist={isTherapist}
        />
      </div>

      <ConsentModal
        open={showConsentModal}
        onAccept={handleConsentAccept}
        onDecline={() => setShowConsentModal(false)}
        isTherapist={isTherapist}
      />
    </div>
  )
}
