import { useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import type { TreatmentPlan, SafetyFlag, Citation } from '@/types'
import api from '@/api/client'
import SafetyFlagBanner from '@/components/therapist/SafetyFlagBanner'
import PlanSection from '@/components/therapist/PlanSection'
import CitationSidebar from '@/components/therapist/CitationSidebar'
import VersionHistory from '@/components/therapist/VersionHistory'
import VersionDiff from '@/components/therapist/VersionDiff'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'

interface PlanReviewData {
  treatment_plan: TreatmentPlan
  safety_flags: SafetyFlag[]
}

export default function PlanReview() {
  const { clientId } = useParams<{ clientId: string }>()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [citationOpen, setCitationOpen] = useState(false)
  const [activeCitations, setActiveCitations] = useState<Citation[]>([])
  const [diffData, setDiffData] = useState<{ v1: number; v2: number; diffs: Record<string, any> } | null>(null)

  const { data, isLoading, error } = useQuery<PlanReviewData>({
    queryKey: ['treatment-plan', clientId],
    queryFn: async () => {
      const { data: payload } = await api.get<{
        treatment_plan: TreatmentPlan | null
        safety_flags: SafetyFlag[]
      }>(`/api/clients/${clientId}`)
      if (!payload.treatment_plan) {
        throw new Error('No treatment plan for this client')
      }
      return {
        treatment_plan: payload.treatment_plan,
        safety_flags: payload.safety_flags ?? [],
      }
    },
    enabled: !!clientId,
  })

  const acknowledgeMutation = useMutation({
    mutationFn: async (flagId: number) => {
      await api.patch(`/api/safety-flags/${flagId}/acknowledge`)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['treatment-plan', clientId] })
    },
  })

  const editMutation = useMutation({
    mutationFn: async ({ planId, therapistContent }: { planId: number; therapistContent: object }) => {
      await api.post(`/api/treatment-plans/${planId}/edit`, {
        therapist_content: therapistContent,
        change_summary: 'Therapist edit',
      })
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['treatment-plan', clientId] })
    },
  })

  const approveMutation = useMutation({
    mutationFn: async (planId: number) => {
      await api.post(`/api/treatment-plans/${planId}/approve`)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['treatment-plan', clientId] })
    },
  })

  const { data: versionsData } = useQuery({
    queryKey: ['treatment-plan-versions', data?.treatment_plan?.id],
    queryFn: async () => {
      const { data: vd } = await api.get(`/api/treatment-plans/${data!.treatment_plan.id}/versions`)
      return vd as any[]
    },
    enabled: !!data?.treatment_plan?.id,
  })

  const handleCompare = async (v1: number, v2: number) => {
    const { data: diffResult } = await api.get(
      `/api/treatment-plans/${data!.treatment_plan.id}/diff?v1=${v1}&v2=${v2}`
    )
    setDiffData({ v1, v2, diffs: (diffResult as any).diffs })
  }

  const handleShowCitations = (citations: Citation[]) => {
    setActiveCitations(citations)
    setCitationOpen(true)
  }

  if (isLoading) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-10 w-60" />
        <Skeleton className="h-24 rounded-xl" />
        <Skeleton className="h-48 rounded-xl" />
        <Skeleton className="h-48 rounded-xl" />
      </div>
    )
  }

  if (error || !data) {
    return (
      <div className="rounded-lg border border-red-200 bg-red-50 p-6 text-center">
        <p className="text-sm text-red-700">Failed to load treatment plan. Please try again.</p>
        <Button variant="outline" size="sm" className="mt-3" onClick={() => navigate(`/therapist/clients/${clientId}`)}>
          Back to Client
        </Button>
      </div>
    )
  }

  const { treatment_plan, safety_flags = [] } = data
  const version = treatment_plan.current_version
  const tc = version?.therapist_content
  const unacknowledgedFlags = safety_flags.filter((f) => !f.acknowledged)
  const hasUnacknowledged = unacknowledgedFlags.length > 0
  const isApproved = treatment_plan.status === 'approved'

  // Edit handler: sends updated full therapist_content with the section text replaced
  const makeEditHandler = (section: string) => (updatedText: string) => {
    if (!tc) return
    const lines = updatedText.split('\n').filter(Boolean)
    const updatedContent = {
      ...tc,
      [section]: lines,
    }
    editMutation.mutate({ planId: treatment_plan.id, therapistContent: updatedContent })
  }

  return (
    <>
      <div className="space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <button
              onClick={() => navigate(`/therapist/clients/${clientId}`)}
              className="mb-1 text-sm text-blue-600 hover:underline"
            >
              &larr; Back to Client
            </button>
            <div className="flex items-center gap-3">
              <h1 className="text-2xl font-semibold text-slate-900">Treatment Plan Review</h1>
              <Badge variant={isApproved ? 'default' : 'secondary'}>{treatment_plan.status}</Badge>
            </div>
          </div>
        </div>

        {/* Safety Flags — always visible, outside tabs */}
        {safety_flags.length > 0 && (
          <SafetyFlagBanner
            flags={safety_flags}
            onAcknowledge={(flagId) => acknowledgeMutation.mutate(flagId)}
            isAcknowledging={acknowledgeMutation.isPending}
          />
        )}

        <Tabs defaultValue="plan">
          <TabsList>
            <TabsTrigger value="plan">Current Plan</TabsTrigger>
            <TabsTrigger value="history">Version History</TabsTrigger>
          </TabsList>

          <TabsContent value="plan" className="space-y-6 mt-4">
            {/* AI Metadata card */}
            {version && tc && (
              <Card>
                <CardContent className="py-4">
                  <p className="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-1">AI Metadata</p>
                  <p className="text-sm text-slate-700">
                    Model: {version.source} · Version {version.version_number}
                  </p>
                </CardContent>
              </Card>
            )}

            {/* Plan Sections */}
            {tc ? (
              <div className="space-y-4">
                <PlanSection
                  title="Presenting Concerns"
                  items={tc.presenting_concerns}
                  citations={tc.presenting_concerns_citations}
                  onSave={makeEditHandler('presenting_concerns')}
                  isSaving={editMutation.isPending}
                  onShowCitations={handleShowCitations}
                />
                <PlanSection
                  title="Goals"
                  items={tc.goals}
                  citations={tc.goals_citations}
                  onSave={makeEditHandler('goals')}
                  isSaving={editMutation.isPending}
                  onShowCitations={handleShowCitations}
                />
                <PlanSection
                  title="Interventions & Approaches"
                  items={tc.interventions}
                  citations={tc.interventions_citations}
                  onSave={makeEditHandler('interventions')}
                  isSaving={editMutation.isPending}
                  onShowCitations={handleShowCitations}
                />
                <PlanSection
                  title="Homework / Between-Session Actions"
                  items={tc.homework}
                  citations={tc.homework_citations}
                  onSave={makeEditHandler('homework')}
                  isSaving={editMutation.isPending}
                  onShowCitations={handleShowCitations}
                />
                <PlanSection
                  title="Strengths & Protective Factors"
                  items={tc.strengths}
                  citations={tc.strengths_citations}
                  onSave={makeEditHandler('strengths')}
                  isSaving={editMutation.isPending}
                  onShowCitations={handleShowCitations}
                />
                {tc.barriers && tc.barriers.length > 0 && (
                  <PlanSection
                    title="Barriers to Treatment"
                    items={tc.barriers}
                    citations={tc.barriers_citations}
                    onSave={makeEditHandler('barriers')}
                    isSaving={editMutation.isPending}
                    onShowCitations={handleShowCitations}
                  />
                )}
                {tc.diagnosis_considerations && tc.diagnosis_considerations.length > 0 && (
                  <PlanSection
                    title="Diagnosis Considerations"
                    items={tc.diagnosis_considerations}
                    onSave={makeEditHandler('diagnosis_considerations')}
                    isSaving={editMutation.isPending}
                    onShowCitations={handleShowCitations}
                  />
                )}
              </div>
            ) : (
              <div className="rounded-lg border border-slate-200 bg-white p-8 text-center">
                <p className="text-sm text-slate-500">
                  No plan version available. Generate a treatment plan from a session first.
                </p>
              </div>
            )}

            {/* Actions */}
            {version && !isApproved && (
              <div className="flex items-center justify-end gap-3 border-t pt-4">
                {hasUnacknowledged && (
                  <p className="mr-auto text-sm text-red-600">
                    Acknowledge all safety flags before approving.
                  </p>
                )}
                <Button
                  disabled={hasUnacknowledged || approveMutation.isPending}
                  onClick={() => approveMutation.mutate(treatment_plan.id)}
                >
                  {approveMutation.isPending ? 'Approving...' : 'Approve & Share with Client'}
                </Button>
              </div>
            )}

            {isApproved && (
              <div className="rounded-lg border border-green-200 bg-green-50 p-4 text-center text-sm text-green-700">
                This treatment plan has been approved and shared with the client.
              </div>
            )}
          </TabsContent>

          <TabsContent value="history" className="space-y-6 mt-4">
            <VersionHistory
              versions={versionsData ?? []}
              onCompare={handleCompare}
            />
            {diffData && (
              <VersionDiff
                version1={diffData.v1}
                version2={diffData.v2}
                diffs={diffData.diffs}
              />
            )}
          </TabsContent>
        </Tabs>
      </div>

      <CitationSidebar
        open={citationOpen}
        onOpenChange={setCitationOpen}
        citations={activeCitations}
      />
    </>
  )
}
