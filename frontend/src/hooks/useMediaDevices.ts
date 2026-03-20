import { useState, useEffect, useCallback } from 'react'

export interface MediaDeviceInfo {
  deviceId: string
  label: string
  kind: MediaDeviceKind
}

export function useMediaDevices() {
  const [devices, setDevices] = useState<MediaDeviceInfo[]>([])
  const [selectedCamera, setSelectedCamera] = useState<string>('')
  const [selectedMic, setSelectedMic] = useState<string>('')
  const [localStream, setLocalStream] = useState<MediaStream | null>(null)
  const [permissionGranted, setPermissionGranted] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const enumerateDevices = useCallback(async () => {
    try {
      const allDevices = await navigator.mediaDevices.enumerateDevices()
      const mediaDevices = allDevices
        .filter((d) => d.kind === 'videoinput' || d.kind === 'audioinput')
        .map((d) => ({
          deviceId: d.deviceId,
          label: d.label || `${d.kind === 'videoinput' ? 'Camera' : 'Microphone'} ${d.deviceId.slice(0, 4)}`,
          kind: d.kind,
        }))
      setDevices(mediaDevices)

      // Auto-select first device if not already selected
      if (!selectedCamera) {
        const cam = mediaDevices.find((d) => d.kind === 'videoinput')
        if (cam) setSelectedCamera(cam.deviceId)
      }
      if (!selectedMic) {
        const mic = mediaDevices.find((d) => d.kind === 'audioinput')
        if (mic) setSelectedMic(mic.deviceId)
      }
    } catch (e) {
      setError('Failed to enumerate devices')
    }
  }, [selectedCamera, selectedMic])

  const requestPermissions = useCallback(async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: selectedCamera ? { deviceId: { exact: selectedCamera } } : true,
        audio: selectedMic ? { deviceId: { exact: selectedMic } } : true,
      })
      setLocalStream(stream)
      setPermissionGranted(true)
      setError(null)
      // Re-enumerate to get labels (labels are only available after permission)
      await enumerateDevices()
      return stream
    } catch (e) {
      const err = e as Error
      if (err.name === 'NotAllowedError') {
        setError('Camera/microphone permission denied. Please allow access in your browser settings.')
      } else if (err.name === 'NotFoundError') {
        setError('No camera or microphone found.')
      } else {
        setError(`Failed to access media devices: ${err.message}`)
      }
      return null
    }
  }, [selectedCamera, selectedMic, enumerateDevices])

  const stopLocalStream = useCallback(() => {
    if (localStream) {
      localStream.getTracks().forEach((track) => track.stop())
      setLocalStream(null)
    }
  }, [localStream])

  useEffect(() => {
    enumerateDevices()
  }, [enumerateDevices])

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (localStream) {
        localStream.getTracks().forEach((track) => track.stop())
      }
    }
  }, [localStream])

  const cameras = devices.filter((d) => d.kind === 'videoinput')
  const microphones = devices.filter((d) => d.kind === 'audioinput')

  return {
    cameras,
    microphones,
    selectedCamera,
    setSelectedCamera,
    selectedMic,
    setSelectedMic,
    localStream,
    permissionGranted,
    error,
    requestPermissions,
    stopLocalStream,
  }
}
