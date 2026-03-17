import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/api/client'
import type { HomeworkItem } from '@/types'
import { Skeleton } from '@/components/ui/skeleton'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import HomeworkChecklist from '@/components/client/HomeworkChecklist'

export default function Homework() {
  const queryClient = useQueryClient()
  const [updatingId, setUpdatingId] = useState<number | null>(null)

  const {
    data: items,
    isLoading,
    error,
  } = useQuery<HomeworkItem[]>({
    queryKey: ['client-homework'],
    queryFn: async () => {
      const { data } = await api.get('/api/my/homework')
      return data
    },
  })

  const mutation = useMutation({
    mutationFn: async (id: number) => {
      setUpdatingId(id)
      const { data } = await api.patch(`/api/homework/${id}`, { completed: true })
      return data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['client-homework'] })
    },
    onSettled: () => {
      setUpdatingId(null)
    },
  })

  const handleToggle = (id: number) => {
    mutation.mutate(id)
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-slate-800">Your Homework</h1>
        <p className="mt-1 text-sm text-slate-500">
          Small steps between sessions that make a big difference
        </p>
      </div>

      {isLoading ? (
        <div className="space-y-3">
          <Skeleton className="h-16 w-full rounded-xl" />
          <Skeleton className="h-16 w-full rounded-xl" />
          <Skeleton className="h-16 w-full rounded-xl" />
        </div>
      ) : error ? (
        <Card className="border-none shadow-sm bg-white/80">
          <CardContent className="py-12 text-center">
            <p className="text-sm text-slate-500">
              Something went wrong loading your homework. Please try again later.
            </p>
          </CardContent>
        </Card>
      ) : items && items.length > 0 ? (
        <Card className="border-none shadow-sm bg-white/80 backdrop-blur-sm">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-teal-800">
              <span className="flex h-8 w-8 items-center justify-center rounded-full bg-teal-100 text-teal-600 text-sm">
                &#10003;
              </span>
              Things to work on
            </CardTitle>
          </CardHeader>
          <CardContent>
            <HomeworkChecklist items={items} onToggle={handleToggle} updatingId={updatingId} />
          </CardContent>
        </Card>
      ) : (
        <Card className="border-none shadow-sm bg-white/80">
          <CardContent className="py-16 text-center">
            <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-teal-50">
              <span className="text-2xl text-teal-400">&#128214;</span>
            </div>
            <h2 className="text-lg font-semibold text-slate-700">No homework yet</h2>
            <p className="mt-2 max-w-sm mx-auto text-sm leading-relaxed text-slate-500">
              Your therapist will add homework items after your next session.
            </p>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
