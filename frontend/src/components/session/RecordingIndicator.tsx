interface RecordingIndicatorProps {
  isRecording: boolean
}

export default function RecordingIndicator({ isRecording }: RecordingIndicatorProps) {
  if (!isRecording) return null

  return (
    <div className="absolute left-4 top-4 z-20 flex items-center gap-2 rounded-full bg-red-600 px-3 py-1.5 text-xs font-medium text-white shadow-lg">
      <span className="h-2 w-2 animate-pulse rounded-full bg-white" />
      Recording
    </div>
  )
}
