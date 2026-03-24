import { Link } from 'react-router-dom'
import { buttonVariants } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { Heart, Shield, UserCircle, Stethoscope } from 'lucide-react'

export default function LoginChoice() {
  return (
    <div className="relative flex min-h-screen flex-col items-center justify-center overflow-hidden bg-gradient-to-br from-teal-50 via-white to-emerald-50">
      {/* Decorative background shapes */}
      <div className="pointer-events-none absolute -top-32 -right-32 h-96 w-96 rounded-full bg-teal-100/40 blur-3xl" />
      <div className="pointer-events-none absolute -bottom-24 -left-24 h-80 w-80 rounded-full bg-emerald-100/40 blur-3xl" />

      <div className="relative z-10 w-full max-w-md px-6">
        {/* Branding */}
        <div className="mb-10 text-center">
          <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-teal-500 to-teal-600 shadow-lg shadow-teal-200">
            <Heart className="h-8 w-8 text-white" />
          </div>
          <h1 className="text-3xl font-bold tracking-tight text-slate-900">
            Appointment Assistant
          </h1>
          <p className="mt-2 text-base text-slate-500">
            Your guided path to mental health care
          </p>
        </div>

        {/* Login options */}
        <div className="space-y-3">
          <Link
            to="/login/client"
            className={cn(
              buttonVariants({ variant: 'outline' }),
              'group relative flex h-16 w-full items-center gap-4 rounded-xl border-slate-200 bg-white/80 px-5 text-left shadow-sm backdrop-blur-sm transition-all hover:border-teal-300 hover:bg-white hover:shadow-md'
            )}
          >
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-teal-50 text-teal-600 transition-colors group-hover:bg-teal-100">
              <UserCircle className="h-5 w-5" />
            </div>
            <div>
              <span className="block text-sm font-semibold text-slate-900">I'm a Client</span>
              <span className="block text-xs font-normal text-slate-500">Access your care and appointments</span>
            </div>
          </Link>

          <Link
            to="/login/therapist"
            className={cn(
              buttonVariants({ variant: 'outline' }),
              'group relative flex h-16 w-full items-center gap-4 rounded-xl border-slate-200 bg-white/80 px-5 text-left shadow-sm backdrop-blur-sm transition-all hover:border-teal-300 hover:bg-white hover:shadow-md'
            )}
          >
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-teal-50 text-teal-600 transition-colors group-hover:bg-teal-100">
              <Stethoscope className="h-5 w-5" />
            </div>
            <div>
              <span className="block text-sm font-semibold text-slate-900">I'm a Therapist</span>
              <span className="block text-xs font-normal text-slate-500">Manage clients and treatment plans</span>
            </div>
          </Link>
        </div>

        {/* Trust signals */}
        <div className="mt-8 flex items-center justify-center gap-2 text-xs text-slate-400">
          <Shield className="h-3.5 w-3.5" />
          <span>HIPAA-compliant &middot; Your data is encrypted and private</span>
        </div>
      </div>
    </div>
  )
}
