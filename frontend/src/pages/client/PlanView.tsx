import { useQuery } from '@tanstack/react-query'
import api from '@/api/client'
import type { TreatmentPlan } from '@/types'
import { Skeleton } from '@/components/ui/skeleton'
import { Card, CardContent } from '@/components/ui/card'
import PlanSectionClient from '@/components/client/PlanSectionClient'

export default function PlanView() {
  const {
    data: plan,
    isLoading,
    error,
  } = useQuery<TreatmentPlan | null>({
    queryKey: ['client-plan'],
    queryFn: async () => {
      try {
        const { data } = await api.get<{ plan: TreatmentPlan }>('/api/my/treatment-plan')
        return data.plan
      } catch (err: unknown) {
        // 404 = no approved plan yet — show friendly empty state
        if (typeof err === 'object' && err !== null && 'response' in err) {
          const res = (err as { response?: { status?: number } }).response
          if (res?.status === 404) {
            return { id: 0, client_id: 0, status: 'none', current_version: undefined } as TreatmentPlan
          }
        }
        throw err
      }
    },
  })

  if (isLoading) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-40 w-full rounded-xl" />
        <Skeleton className="h-40 w-full rounded-xl" />
        <Skeleton className="h-40 w-full rounded-xl" />
      </div>
    )
  }

  if (error) {
    return (
      <Card className="border-none shadow-sm bg-white/80">
        <CardContent className="py-12 text-center">
          <p className="text-sm text-slate-500">
            Something went wrong loading your plan. Please try again later.
          </p>
        </CardContent>
      </Card>
    )
  }

  const clientContent = plan?.current_version?.client_content

  if (!clientContent) {
    return (
      <Card className="border-none shadow-sm bg-white/80">
        <CardContent className="py-16 text-center">
          <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-teal-50">
            <span className="text-2xl text-teal-400">&#128218;</span>
          </div>
          <h2 className="text-lg font-semibold text-slate-700">No plan shared yet</h2>
          <p className="mt-2 max-w-sm mx-auto text-sm leading-relaxed text-slate-500">
            Your therapist hasn't shared a plan yet. Check back after your next session!
          </p>
        </CardContent>
      </Card>
    )
  }

  const createdAt = plan?.current_version?.created_at

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-slate-800">Your Treatment Plan</h1>
        <p className="mt-1 text-sm text-slate-500">
          A personalized plan created together with your therapist
        </p>
      </div>

      {/* What We Talked About */}
      {clientContent.what_we_talked_about && (
        <PlanSectionClient
          icon={<span className="text-sm">&#127919;</span>}
          title="What We Talked About"
        >
          <p className="text-sm leading-relaxed text-slate-700">{clientContent.what_we_talked_about}</p>
        </PlanSectionClient>
      )}

      {/* Your Goals */}
      {clientContent.your_goals.length > 0 && (
        <PlanSectionClient
          icon={<span className="text-sm">&#127793;</span>}
          title="Your Goals"
        >
          <ul className="space-y-2">
            {clientContent.your_goals.map((g, i) => (
              <li key={i} className="flex items-start gap-2 text-sm leading-relaxed text-slate-700">
                <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-teal-400" />
                {g}
              </li>
            ))}
          </ul>
        </PlanSectionClient>
      )}

      {/* Things to Try */}
      {clientContent.things_to_try.length > 0 && (
        <PlanSectionClient
          icon={<span className="text-sm">&#128221;</span>}
          title="Things to Try Before Next Session"
        >
          <ul className="space-y-2">
            {clientContent.things_to_try.map((item, i) => (
              <li key={i} className="flex items-start gap-2 text-sm leading-relaxed text-slate-700">
                <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-teal-400" />
                {item}
              </li>
            ))}
          </ul>
        </PlanSectionClient>
      )}

      {/* Your Strengths */}
      {clientContent.your_strengths.length > 0 && (
        <PlanSectionClient
          icon={<span className="text-sm">&#128170;</span>}
          title="Your Strengths"
        >
          <div className="flex flex-wrap gap-2">
            {clientContent.your_strengths.map((item, i) => (
              <span
                key={i}
                className="rounded-full bg-emerald-50 border border-emerald-200 px-4 py-1.5 text-sm text-emerald-700"
              >
                {item}
              </span>
            ))}
          </div>
        </PlanSectionClient>
      )}

      {/* Next Steps */}
      {clientContent.next_steps && clientContent.next_steps.length > 0 && (
        <PlanSectionClient
          icon={<span className="text-sm">&#128161;</span>}
          title="Next Steps"
        >
          <ul className="space-y-2">
            {clientContent.next_steps.map((item, i) => (
              <li key={i} className="flex items-start gap-2 text-sm leading-relaxed text-slate-700">
                <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-teal-400" />
                {item}
              </li>
            ))}
          </ul>
        </PlanSectionClient>
      )}

      {/* Last updated */}
      {createdAt && (
        <p className="text-center text-xs text-slate-400 pt-2">
          Last updated{' '}
          {new Date(createdAt).toLocaleDateString('en-US', {
            month: 'long',
            day: 'numeric',
            year: 'numeric',
          })}
        </p>
      )}
    </div>
  )
}
