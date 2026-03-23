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
const PreJoinScreen = lazy(() => import('./pages/therapist/PreJoinScreen'))
const LiveSession = lazy(() => import('./pages/therapist/LiveSession'))
const PostSessionReview = lazy(() => import('./pages/therapist/PostSessionReview'))

// Client pages
const ClientDashboard = lazy(() => import('./pages/client/Dashboard'))
const PlanView = lazy(() => import('./pages/client/PlanView'))
const Sessions = lazy(() => import('./pages/client/Sessions'))
const Homework = lazy(() => import('./pages/client/Homework'))
const JoinLiveSession = lazy(() => import('./pages/client/JoinLiveSession'))
const Onboard = lazy(() => import('./pages/client/Onboard'))

function PageLoader() {
  return <div className="flex items-center justify-center h-64 text-muted-foreground">Loading...</div>
}

export default function App() {
  return (
    <Suspense fallback={<PageLoader />}>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/" element={<Navigate to="/login" replace />} />
        <Route path="/onboard/:slug" element={<Onboard />} />

        {/* Therapist routes */}
        <Route element={<TherapistLayout />}>
          <Route path="/therapist/dashboard" element={<TherapistDashboard />} />
          <Route path="/therapist/clients" element={<TherapistDashboard />} />
          <Route path="/therapist/clients/:clientId" element={<ClientDetail />} />
          <Route path="/therapist/sessions/new" element={<NewSession />} />
          <Route path="/therapist/clients/:clientId/plan" element={<PlanReview />} />
          <Route path="/therapist/clients/:clientId/live" element={<PreJoinScreen />} />
          <Route path="/therapist/evaluation" element={<Evaluation />} />
          <Route path="/therapist/session/:sessionId/review" element={<PostSessionReview />} />
        </Route>

        {/* Live session (full-screen, outside layout) */}
        <Route path="/therapist/session/:sessionId/live" element={<LiveSession />} />

        {/* Client join live session (full-screen, outside layout) */}
        <Route path="/client/session/:sessionId/join" element={<JoinLiveSession />} />

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
