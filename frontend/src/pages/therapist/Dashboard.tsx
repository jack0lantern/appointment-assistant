import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import type { ClientProfile } from '@/types'
import api from '@/api/client'
import ClientCard from '@/components/therapist/ClientCard'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'

export default function Dashboard() {
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

  return (
    <div className="space-y-6">
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
