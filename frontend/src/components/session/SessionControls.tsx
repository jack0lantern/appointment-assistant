import { useCallback } from 'react'
import { useLocalParticipant } from '@livekit/components-react'
import { Button } from '@/components/ui/button'

interface SessionControlsProps {
  isRecording: boolean
  canRecord: boolean
  onToggleRecording: () => void
  onEndSession: () => void
  isTherapist: boolean
}

export default function SessionControls({
  isRecording,
  canRecord,
  onToggleRecording,
  onEndSession,
  isTherapist,
}: SessionControlsProps) {
  const { localParticipant } = useLocalParticipant()

  const isCameraEnabled = localParticipant.isCameraEnabled
  const isMicEnabled = localParticipant.isMicrophoneEnabled

  const toggleCamera = useCallback(async () => {
    await localParticipant.setCameraEnabled(!isCameraEnabled)
  }, [localParticipant, isCameraEnabled])

  const toggleMic = useCallback(async () => {
    await localParticipant.setMicrophoneEnabled(!isMicEnabled)
  }, [localParticipant, isMicEnabled])

  return (
    <div className="flex items-center justify-center gap-3 rounded-xl bg-slate-900 px-6 py-4">
      {/* Mic toggle */}
      <Button
        variant={isMicEnabled ? 'secondary' : 'destructive'}
        size="lg"
        onClick={toggleMic}
        className="h-12 w-12 rounded-full p-0"
        title={isMicEnabled ? 'Mute' : 'Unmute'}
      >
        {isMicEnabled ? (
          <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z" />
            <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
            <line x1="12" x2="12" y1="19" y2="22" />
          </svg>
        ) : (
          <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <line x1="2" x2="22" y1="2" y2="22" />
            <path d="M18.89 13.23A7.12 7.12 0 0 0 19 12v-2" />
            <path d="M5 10v2a7 7 0 0 0 12 5.29" />
            <path d="M15 9.34V5a3 3 0 0 0-5.68-1.33" />
            <path d="M9 9v3a3 3 0 0 0 5.12 2.12" />
            <line x1="12" x2="12" y1="19" y2="22" />
          </svg>
        )}
      </Button>

      {/* Camera toggle */}
      <Button
        variant={isCameraEnabled ? 'secondary' : 'destructive'}
        size="lg"
        onClick={toggleCamera}
        className="h-12 w-12 rounded-full p-0"
        title={isCameraEnabled ? 'Turn off camera' : 'Turn on camera'}
      >
        {isCameraEnabled ? (
          <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="m16 13 5.223 3.482a.5.5 0 0 0 .777-.416V7.87a.5.5 0 0 0-.752-.432L16 10.5" />
            <rect x="2" y="6" width="14" height="12" rx="2" />
          </svg>
        ) : (
          <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M10.66 6H14a2 2 0 0 1 2 2v2.5l5.248-3.062A.5.5 0 0 1 22 7.87v8.196" />
            <path d="M16 16a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h2" />
            <line x1="2" x2="22" y1="2" y2="22" />
          </svg>
        )}
      </Button>

      {/* Recording toggle (therapist only) */}
      {isTherapist && (
        <Button
          variant={isRecording ? 'destructive' : 'secondary'}
          size="lg"
          onClick={onToggleRecording}
          disabled={!canRecord && !isRecording}
          className="h-12 rounded-full px-4"
          title={isRecording ? 'Stop recording' : 'Start recording'}
        >
          <span className={`mr-2 inline-block h-3 w-3 rounded-full ${isRecording ? 'animate-pulse bg-red-400' : 'bg-slate-400'}`} />
          {isRecording ? 'Stop Rec' : 'Record'}
        </Button>
      )}

      {/* End session */}
      <Button
        variant="destructive"
        size="lg"
        onClick={onEndSession}
        className="ml-4 h-12 rounded-full px-6"
      >
        End Session
      </Button>
    </div>
  )
}
