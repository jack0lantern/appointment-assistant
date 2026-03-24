import { createContext, useContext, useState, useCallback, type ReactNode } from 'react'
import { flushSync } from 'react-dom'
import type { User } from '@/types'
import api from '@/api/client'

type LoginRole = 'client' | 'therapist'

export interface LoginResult {
  user: User
  needs_onboarding?: boolean
  onboard_slug?: string
}

interface AuthContextType {
  user: User | null
  login: (email: string, password: string, role: LoginRole) => Promise<LoginResult>
  logout: () => void
  isAuthenticated: boolean
}

const AuthContext = createContext<AuthContextType | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(() => {
    const stored = localStorage.getItem('user')
    return stored ? JSON.parse(stored) : null
  })

  const login = useCallback(async (email: string, password: string, role: LoginRole): Promise<LoginResult> => {
    const path = role === 'therapist' ? '/api/auth/therapist/login' : '/api/auth/client/login'
    const { data } = await api.post(path, { email, password })
    localStorage.setItem('token', data.token)
    localStorage.setItem('user', JSON.stringify(data.user))
    // Commit user before callers run navigate(); avoids layouts seeing user===null (blank screen with return null).
    flushSync(() => {
      setUser(data.user)
    })
    // #region agent log
    fetch('http://127.0.0.1:7257/ingest/e733306d-eb49-4862-a616-3c2c4748159b', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Debug-Session-Id': '7850df' },
      body: JSON.stringify({
        sessionId: '7850df',
        location: 'AuthContext.tsx:login',
        message: 'login flushSync applied',
        data: { hypothesisId: 'H1', role: data.user?.role, id: data.user?.id },
        timestamp: Date.now(),
      }),
    }).catch(() => {})
    // #endregion
    return { user: data.user, needs_onboarding: data.needs_onboarding, onboard_slug: data.onboard_slug }
  }, [])

  const logout = useCallback(() => {
    localStorage.removeItem('token')
    localStorage.removeItem('user')
    setUser(null)
  }, [])

  return (
    <AuthContext.Provider value={{ user, login, logout, isAuthenticated: !!user }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within AuthProvider')
  return ctx
}
