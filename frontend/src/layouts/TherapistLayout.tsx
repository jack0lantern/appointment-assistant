import { useEffect } from 'react'
import { Outlet, NavLink, useNavigate } from 'react-router-dom'
import { useAuth } from '@/context/AuthContext'
import { Button } from '@/components/ui/button'
import PrivacyDisclaimer from '@/components/shared/PrivacyDisclaimer'
import ChatWidget from '@/components/chat/ChatWidget'

export default function TherapistLayout() {
  const { user, logout } = useAuth()
  const navigate = useNavigate()

  useEffect(() => {
    if (!user) {
      navigate('/login/therapist', { replace: true })
      return
    }
    if (user.role !== 'therapist' && user.role !== 'admin') {
      navigate('/client/dashboard', { replace: true })
    }
  }, [user, navigate])

  if (!user) return null

  const handleLogout = () => {
    logout()
    navigate('/login/therapist')
  }

  const linkClass = ({ isActive }: { isActive: boolean }) =>
    `block px-4 py-2 rounded-md text-sm font-medium transition-colors ${
      isActive ? 'bg-blue-100 text-blue-900' : 'text-slate-600 hover:bg-slate-100'
    }`

  return (
    <div className="flex h-screen bg-slate-50">
      <aside className="w-56 border-r bg-white flex flex-col">
        <div className="p-4 border-b">
          <h1 className="text-lg font-semibold text-slate-900">Appointment Assistant</h1>
          <p className="text-xs text-slate-500">Therapist Portal</p>
        </div>
        <nav className="flex-1 p-3 space-y-1">
          <NavLink to="/therapist/dashboard" className={linkClass}>Dashboard</NavLink>
          <NavLink to="/therapist/clients" className={linkClass}>Clients</NavLink>
        </nav>
        <div className="p-3 border-t">
          <p className="text-xs text-slate-500 mb-2">{user?.name}</p>
          <Button variant="outline" size="sm" onClick={handleLogout} className="w-full">
            Logout
          </Button>
        </div>
      </aside>
      <main className="flex-1 flex flex-col overflow-hidden">
        <div className="flex-1 overflow-y-auto p-6">
          <Outlet />
        </div>
        <PrivacyDisclaimer />
      </main>
      <ChatWidget contextType="general" />
    </div>
  )
}
