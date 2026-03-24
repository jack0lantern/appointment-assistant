import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '@/context/AuthContext'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Stethoscope, Shield, ArrowLeft } from 'lucide-react'

export default function TherapistLogin() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const { login } = useAuth()
  const navigate = useNavigate()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      await login(email, password, 'therapist')
      navigate('/therapist/dashboard')
    } catch (err: unknown) {
      const msg = err && typeof err === 'object' && 'response' in err
        ? (err as { response?: { data?: { error?: string } } }).response?.data?.error ?? 'Invalid email or password'
        : 'Invalid email or password'
      setError(msg)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-gradient-to-br from-slate-50 via-white to-teal-50">
      <div className="pointer-events-none absolute -top-32 -left-32 h-96 w-96 rounded-full bg-slate-100/60 blur-3xl" />
      <div className="pointer-events-none absolute -bottom-24 -right-24 h-80 w-80 rounded-full bg-teal-100/30 blur-3xl" />

      <div className="relative z-10 w-full max-w-sm px-6">
        <div className="mb-8 text-center">
          <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-slate-700 to-slate-800 shadow-lg shadow-slate-300">
            <Stethoscope className="h-7 w-7 text-white" />
          </div>
        </div>

        <Card className="border-slate-200/80 shadow-lg">
          <CardHeader className="text-center pb-4">
            <CardTitle className="text-xl text-slate-900">Therapist Portal</CardTitle>
            <p className="text-sm text-slate-500">Sign in to manage your practice</p>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="email" className="text-slate-700">Email</Label>
                <Input
                  id="email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@example.com"
                  required
                  className="h-11"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="password" className="text-slate-700">Password</Label>
                <Input
                  id="password"
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  className="h-11"
                />
              </div>
              {error && (
                <div className="rounded-lg bg-red-50 border border-red-100 px-3 py-2 text-sm text-red-600">
                  {error}
                </div>
              )}
              <Button
                type="submit"
                className="h-11 w-full bg-gradient-to-r from-slate-700 to-slate-800 hover:from-slate-800 hover:to-slate-900 shadow-sm"
                disabled={loading}
              >
                {loading ? 'Signing in...' : 'Sign In'}
              </Button>
            </form>

            <div className="mt-5 text-center">
              <Link to="/login" className="inline-flex items-center gap-1.5 text-sm text-slate-500 hover:text-slate-700 transition-colors">
                <ArrowLeft className="h-3.5 w-3.5" />
                Back
              </Link>
            </div>

            <div className="mt-5 rounded-lg bg-slate-50 p-3 text-xs text-slate-500 text-center">
              <p>Demo: <span className="font-medium">therapist@demo.health</span> / demo123</p>
            </div>
          </CardContent>
        </Card>

        <div className="mt-6 flex items-center justify-center gap-2 text-xs text-slate-400">
          <Shield className="h-3.5 w-3.5" />
          <span>HIPAA-compliant &middot; Encrypted</span>
        </div>
      </div>
    </div>
  )
}
