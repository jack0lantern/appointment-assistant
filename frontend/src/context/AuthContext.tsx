import { createContext, useContext, useState, useCallback, type ReactNode } from 'react'
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
    setUser(data.user)
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
