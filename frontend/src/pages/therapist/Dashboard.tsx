import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import type { ClientProfile, DraftPlanSummary, TherapistAppointment } from '@/types'
import api from '@/api/client'
import ClientCard from '@/components/therapist/ClientCard'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'

export default function Dashboard() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [showAddForm, setShowAddForm] = useState(false)
  const [newClientName, setNewClientName] = useState('')

  const { data: clients, isLoading, error } = useQuery<ClientProfile[]>({
    queryKey: ['clients'],
    queryFn: async () => {
      const { data } = await api.get<ClientProfile[]>('/api/clients')
      return data
    },
  })

  const { data: draftPlans } = useQuery<DraftPlanSummary[]>({
    queryKey: ['draftPlans'],
    queryFn: async () => {
      const { data } = await api.get<DraftPlanSummary[]>('/api/treatment-plans/draft')
      return data
    },
  })

  const { data: appointmentsData } = useQuery<{ appointments: TherapistAppointment[] }>({
    queryKey: ['therapistAppointments'],
    queryFn: async () => {
      const { data } = await api.get<{ appointments: TherapistAppointment[] }>('/api/therapist/appointments')
      return data
    },
  })

  const upcomingAppointments = appointmentsData?.appointments ?? []

  const addClientMutation = useMutation({
    mutationFn: async (name: string) => {
      const { data } = await api.post<ClientProfile>('/api/clients', { name })
      return data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['clients'] })
      setNewClientName('')
      setShowAddForm(false)
    },
  })

  const handleAddClient = (e: React.FormEvent) => {
    e.preventDefault()
    const trimmed = newClientName.trim()
    if (trimmed) {
      addClientMutation.mutate(trimmed)
    }
  }

  if (isLoading) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <Skeleton className="h-8 w-40" />
          <Skeleton className="h-8 w-28" />
        </div>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-36 rounded-xl" />
          ))}
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="rounded-lg border border-red-200 bg-red-50 p-6 text-center">
        <p className="text-sm text-red-700">
          Failed to load clients. Please try again.
        </p>
      </div>
    )
  }

  const hasDraftPlans = draftPlans !== undefined && draftPlans.length > 0
  const allSubmitted = draftPlans !== undefined && draftPlans.length === 0 && (clients?.length ?? 0) > 0

  return (
    <div className="space-y-6">
      {upcomingAppointments.length > 0 && (
        <div>
          <h2 className="mb-3 text-lg font-semibold text-slate-900">Upcoming Appointments</h2>
          <div className="divide-y divide-slate-100 rounded-xl border border-slate-200 bg-white">
            {upcomingAppointments.map((apt) => (
              <button
                key={apt.session_id}
                className="flex w-full items-center justify-between px-4 py-3 text-left transition-colors hover:bg-slate-50"
                onClick={() => navigate(`/therapist/clients/${apt.client_id}`)}
              >
                <div className="text-left">
                  <span className="font-medium text-slate-900">{apt.client_name}</span>
                  <p className="text-sm text-slate-500">
                    {new Date(apt.session_date).toLocaleDateString('en-US', {
                      weekday: 'short',
                      month: 'short',
                      day: 'numeric',
                      year: 'numeric',
                      timeZone: 'America/Denver',
                    })}{' '}
                    at {new Date(apt.session_date).toLocaleTimeString('en-US', {
                      hour: 'numeric',
                      minute: '2-digit',
                      timeZone: 'America/Denver',
                    })}{' '}
                    · {apt.duration_minutes} min
                  </p>
                </div>
              </button>
            ))}
          </div>
        </div>
      )}

      {(hasDraftPlans || allSubmitted) && (
        <div>
          <h2 className="mb-3 text-lg font-semibold text-slate-900">Pending Plans</h2>
          {allSubmitted ? (
            <div className="flex flex-col items-center justify-center rounded-xl border border-green-200 bg-green-50 py-8 text-center">
              <span className="text-3xl">🎉</span>
              <p className="mt-2 font-semibold text-green-800">All plans submitted!</p>
              <p className="mt-1 text-sm text-green-600">Every client has received their treatment plan.</p>
            </div>
          ) : (
            <div className="divide-y divide-slate-100 rounded-xl border border-slate-200 bg-white">
              {draftPlans!.map((plan) => (
                <button
                  key={plan.plan_id}
                  className="flex w-full items-center justify-between px-4 py-3 text-left transition-colors hover:bg-slate-50"
                  onClick={() => navigate(`/therapist/clients/${plan.client_id}`)}
                >
                  <span className="font-medium text-slate-900">{plan.client_name}</span>
                  <span className="text-sm text-slate-500">
                    {new Date(plan.created_at).toLocaleDateString()}
                  </span>
                </button>
              ))}
            </div>
          )}
        </div>
      )}

      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">Clients</h1>
          <p className="text-sm text-slate-500">
            {clients?.length ?? 0} {(clients?.length ?? 0) === 1 ? 'client' : 'clients'}
          </p>
        </div>
        <Button onClick={() => setShowAddForm(!showAddForm)}>
          {showAddForm ? 'Cancel' : 'Add Client'}
        </Button>
      </div>

      {showAddForm && (
        <form
          onSubmit={handleAddClient}
          className="flex items-end gap-3 rounded-lg border bg-white p-4"
        >
          <div className="flex-1">
            <label className="mb-1 block text-sm font-medium text-slate-700">
              Client Name
            </label>
            <Input
              placeholder="Enter client name"
              value={newClientName}
              onChange={(e) => setNewClientName(e.target.value)}
              autoFocus
            />
          </div>
          <Button type="submit" disabled={addClientMutation.isPending || !newClientName.trim()}>
            {addClientMutation.isPending ? 'Adding...' : 'Add'}
          </Button>
        </form>
      )}

      {addClientMutation.isError && (
        <div className="rounded-lg bg-red-50 p-3 text-sm text-red-700">
          Failed to add client. Please try again.
        </div>
      )}

      {clients && clients.length === 0 ? (
        <div className="flex flex-col items-center justify-center rounded-xl border-2 border-dashed border-slate-200 py-16">
          <p className="text-lg font-medium text-slate-500">No clients yet</p>
          <p className="mt-1 text-sm text-slate-400">
            Click "Add Client" to get started.
          </p>
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {clients?.map((client) => (
            <ClientCard key={client.id} client={client} />
          ))}
        </div>
      )}
    </div>
  )
}
