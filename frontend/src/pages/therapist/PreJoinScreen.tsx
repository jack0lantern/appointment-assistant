import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useMutation, useQuery } from '@tanstack/react-query'
import api from '@/api/client'
import type { ClientProfile, Session } from '@/types'
import { useMediaDevices } from '@/hooks/useMediaDevices'
import { Button } from '@/components/ui/button'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Label } from '@/components/ui/label'

export default function PreJoinScreen() {
  const { clientId } = useParams<{ clientId: string }>()
  const navigate = useNavigate()
  const videoRef = useRef<HTMLVideoElement>(null)

  const {
    cameras,
    microphones,
    selectedCamera,
    setSelectedCamera,
    selectedMic,
    setSelectedMic,
    localStream,
    permissionGranted,
    error: mediaError,
    requestPermissions,
    stopLocalStream,
  } = useMediaDevices()

  // Fetch client info
  const { data: clientData } = useQuery<{ client: ClientProfile }>({
    queryKey: ['client', clientId],
    queryFn: async () => {
      const { data } = await api.get(`/api/clients/${clientId}`)
      return data
    },
    enabled: !!clientId,
  })

  const clientName = clientData?.client?.name ?? `Client #${clientId}`

  // Request permissions on mount
  useEffect(() => {
    requestPermissions()
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  // Attach local stream to video preview
  useEffect(() => {
    if (videoRef.current && localStream) {
      videoRef.current.srcObject = localStream
    }
  }, [localStream])

  // Create live session
  const createSession = useMutation({
    mutationFn: async () => {
      const { data } = await api.post<Session>(`/api/clients/${clientId}/sessions/live`, {
        duration_minutes: 50,
      })
      return data
    },
    onSuccess: (session) => {
      stopLocalStream()
      navigate(`/therapist/session/${session.id}/live`, {
        state: { clientId: Number(clientId), clientName },
      })
    },
  })

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <button
          onClick={() => navigate(`/therapist/clients/${clientId}`)}
          className="mb-1 text-sm text-blue-600 hover:underline"
        >
          &larr; Back to {clientName}
        </button>
        <h1 className="text-2xl font-semibold text-slate-900">Start Live Session</h1>
        <p className="text-sm text-slate-500">with {clientName}</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-slate-900">Camera Preview</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {/* Video preview */}
          <div className="relative aspect-video overflow-hidden rounded-lg bg-slate-900">
            {localStream ? (
              <video
                ref={videoRef}
                autoPlay
                playsInline
                muted
                className="h-full w-full object-cover"
              />
            ) : (
              <div className="flex h-full items-center justify-center text-sm text-slate-400">
                {mediaError ?? 'Requesting camera access...'}
              </div>
            )}
          </div>

          {/* Device selection */}
          {permissionGranted && (
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="camera-select">Camera</Label>
                <select
                  id="camera-select"
                  value={selectedCamera}
                  onChange={(e) => setSelectedCamera(e.target.value)}
                  className="w-full rounded-md border border-slate-200 px-3 py-2 text-sm"
                >
                  {cameras.map((cam) => (
                    <option key={cam.deviceId} value={cam.deviceId}>
                      {cam.label}
                    </option>
                  ))}
                </select>
              </div>
              <div className="space-y-2">
                <Label htmlFor="mic-select">Microphone</Label>
                <select
                  id="mic-select"
                  value={selectedMic}
                  onChange={(e) => setSelectedMic(e.target.value)}
                  className="w-full rounded-md border border-slate-200 px-3 py-2 text-sm"
                >
                  {microphones.map((mic) => (
                    <option key={mic.deviceId} value={mic.deviceId}>
                      {mic.label}
                    </option>
                  ))}
                </select>
              </div>
            </div>
          )}

          {mediaError && (
            <div className="rounded-lg bg-red-50 p-3 text-sm text-red-700">{mediaError}</div>
          )}

          {createSession.isError && (
            <div className="rounded-lg bg-red-50 p-3 text-sm text-red-700">
              Failed to create session. Please try again.
            </div>
          )}

          <div className="flex justify-end gap-3">
            <Button
              variant="outline"
              onClick={() => navigate(`/therapist/clients/${clientId}`)}
            >
              Cancel
            </Button>
            <Button
              onClick={() => createSession.mutate()}
              disabled={!permissionGranted || createSession.isPending}
            >
              {createSession.isPending ? 'Starting...' : 'Start Session'}
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
