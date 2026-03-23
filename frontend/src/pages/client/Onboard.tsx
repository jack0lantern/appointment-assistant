import { useEffect, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import api from '@/api/client'
import ChatWidget from '@/components/chat/ChatWidget'

interface OnboardResponse {
  conversation_id: string
  therapist_name: string
  context_type: string
  welcome_message: string
}

export default function Onboard() {
  const { slug } = useParams<{ slug: string }>()
  const navigate = useNavigate()
  const [data, setData] = useState<OnboardResponse | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!slug) return

    const token = localStorage.getItem('token')
    if (!token) {
      // Preserve slug through auth — redirect to login with return URL
      localStorage.setItem('onboard_slug', slug)
      navigate('/login', { replace: true })
      return
    }

    api
      .get<OnboardResponse>(`/api/onboard/${slug}`)
      .then(({ data }) => {
        setData(data)
        localStorage.removeItem('onboard_slug')
      })
      .catch((err) => {
        if (err.response?.status === 404) {
          setError('This onboarding link is invalid or has expired.')
        } else if (err.response?.status === 401) {
          localStorage.setItem('onboard_slug', slug)
          navigate('/login', { replace: true })
        } else {
          setError('Something went wrong. Please try again.')
        }
      })
      .finally(() => setLoading(false))
  }, [slug, navigate])

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-50">
        <div className="text-center text-slate-500">
          <div className="h-8 w-8 mx-auto mb-3 animate-spin rounded-full border-2 border-teal-600 border-t-transparent" />
          <p className="text-sm">Setting up your onboarding...</p>
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-50">
        <div className="max-w-md rounded-xl bg-white p-8 shadow-lg text-center">
          <p className="text-red-600 font-medium mb-2">Oops</p>
          <p className="text-sm text-slate-600">{error}</p>
          <button
            onClick={() => navigate('/login')}
            className="mt-4 rounded-lg bg-teal-600 px-4 py-2 text-sm text-white hover:bg-teal-700"
          >
            Go to Login
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-slate-50">
      {/* Welcome banner */}
      <div className="bg-teal-600 px-6 py-8 text-center text-white">
        <h1 className="text-2xl font-bold">
          {data?.therapist_name
            ? `Welcome — you've been referred to ${data.therapist_name}`
            : 'Welcome to your onboarding'}
        </h1>
        <p className="mt-2 text-teal-100 text-sm">
          Our assistant will guide you through the process step by step.
        </p>
      </div>

      {/* Chat widget auto-opened with the initialized conversation */}
      <ChatWidget
        contextType="onboarding"
        initialConversationId={data?.conversation_id}
      />
    </div>
  )
}
