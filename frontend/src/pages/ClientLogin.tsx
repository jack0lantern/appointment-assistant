import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '@/context/AuthContext'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

export default function ClientLogin() {
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
      const result = await login(email, password, 'client')
      // Check for pending onboard slug (set by /onboard/:slug before auth redirect)
      const pendingSlug = localStorage.getItem('onboard_slug')
      if (pendingSlug) {
        localStorage.removeItem('onboard_slug')
        navigate(`/onboard/${pendingSlug}`)
      } else if (result.needs_onboarding && result.onboard_slug) {
        navigate(`/onboard/${result.onboard_slug}`)
      } else {
        navigate('/client/dashboard')
      }
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
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-teal-50 to-white">
      <Card className="w-full max-w-sm shadow-lg border-teal-100">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl text-teal-900">Client Login</CardTitle>
          <p className="text-sm text-muted-foreground">Sign in to access your care</p>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </div>
            {error && <p className="text-sm text-red-600">{error}</p>}
            <Button type="submit" className="w-full" disabled={loading}>
              {loading ? 'Signing in...' : 'Sign In'}
            </Button>
          </form>
          <div className="mt-4 text-center">
            <Link to="/login" className="text-sm text-teal-600 hover:text-teal-800">
              ← Back to login
            </Link>
          </div>
          <div className="mt-4 text-xs text-muted-foreground text-center space-y-1">
            <p>Demo: client@demo.health / demo123</p>
            <p>Demo (new patient flow): jordan.kim@demo.health / demo123</p>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
