import { useEffect } from 'react'
import { Outlet, NavLink, useNavigate } from 'react-router-dom'
import { useAuth } from '@/context/AuthContext'
import { Button } from '@/components/ui/button'
import PrivacyDisclaimer from '@/components/shared/PrivacyDisclaimer'

export default function ClientLayout() {
  const { user, logout } = useAuth()
  const navigate = useNavigate()

  useEffect(() => {
    if (!user) {
      navigate('/login', { replace: true })
    }
  }, [user, navigate])

  if (!user) return null

  const handleLogout = () => {
    logout()
    navigate('/login')
  }

  const linkClass = ({ isActive }: { isActive: boolean }) =>
    `px-4 py-2 rounded-full text-sm font-medium transition-colors ${
      isActive ? 'bg-teal-100 text-teal-900' : 'text-slate-600 hover:bg-teal-50'
    }`

  return (
    <div className="min-h-screen bg-gradient-to-br from-teal-50 to-white">
      <header className="bg-white border-b shadow-sm">
        <div className="max-w-4xl mx-auto px-6 py-3 flex items-center justify-between">
          <div>
            <h1 className="text-lg font-semibold text-teal-900">Tava Health</h1>
          </div>
          <nav className="flex items-center gap-2">
            <NavLink to="/client/dashboard" className={linkClass}>Home</NavLink>
            <NavLink to="/client/plan" className={linkClass}>My Plan</NavLink>
            <NavLink to="/client/sessions" className={linkClass}>Sessions</NavLink>
            <NavLink to="/client/homework" className={linkClass}>Homework</NavLink>
          </nav>
          <div className="flex items-center gap-3">
            <span className="text-sm text-slate-500">{user?.name}</span>
            <Button variant="outline" size="sm" onClick={handleLogout}>Logout</Button>
          </div>
        </div>
      </header>
      <main className="max-w-4xl mx-auto px-6 py-8">
        <Outlet />
      </main>
      <PrivacyDisclaimer />
    </div>
  )
}
