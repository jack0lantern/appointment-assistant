import { Routes, Route, Navigate } from 'react-router-dom'
import { lazy, Suspense } from 'react'
import TherapistLayout from './layouts/TherapistLayout'
import ClientLayout from './layouts/ClientLayout'
import Login from './pages/Login'

// Therapist pages — lazy loaded so app boots even before agent files exist
const TherapistDashboard = lazy(() => import('./pages/therapist/Dashboard'))
const ClientDetail = lazy(() => import('./pages/therapist/ClientDetail'))
const NewSession = lazy(() => import('./pages/therapist/NewSession'))
const PlanReview = lazy(() => import('./pages/therapist/PlanReview'))
const Evaluation = lazy(() => import('./pages/therapist/Evaluation'))

// Client pages
const ClientDashboard = lazy(() => import('./pages/client/Dashboard'))
const PlanView = lazy(() => import('./pages/client/PlanView'))
const Sessions = lazy(() => import('./pages/client/Sessions'))
const Homework = lazy(() => import('./pages/client/Homework'))

function PageLoader() {
  return <div className="flex items-center justify-center h-64 text-muted-foreground">Loading...</div>
}

export default function App() {
  return (
    <Suspense fallback={<PageLoader />}>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/" element={<Navigate to="/login" replace />} />

        {/* Therapist routes */}
        <Route element={<TherapistLayout />}>
          <Route path="/therapist/dashboard" element={<TherapistDashboard />} />
          <Route path="/therapist/clients" element={<TherapistDashboard />} />
          <Route path="/therapist/clients/:clientId" element={<ClientDetail />} />
          <Route path="/therapist/sessions/new" element={<NewSession />} />
          <Route path="/therapist/clients/:clientId/plan" element={<PlanReview />} />
          <Route path="/therapist/evaluation" element={<Evaluation />} />
        </Route>

        {/* Client routes */}
        <Route element={<ClientLayout />}>
          <Route path="/client/dashboard" element={<ClientDashboard />} />
          <Route path="/client/plan" element={<PlanView />} />
          <Route path="/client/sessions" element={<Sessions />} />
          <Route path="/client/homework" element={<Homework />} />
        </Route>
      </Routes>
    </Suspense>
  )
}
