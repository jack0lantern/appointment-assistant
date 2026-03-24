import { Card, CardContent } from '@/components/ui/card'
import { Sparkles } from 'lucide-react'

interface WelcomeCardProps {
  name: string
}

function getGreeting(): string {
  const hour = new Date().getHours()
  if (hour < 12) return 'Good morning'
  if (hour < 17) return 'Good afternoon'
  return 'Good evening'
}

export default function WelcomeCard({ name }: WelcomeCardProps) {
  const today = new Date().toLocaleDateString('en-US', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  })

  return (
    <Card className="relative overflow-hidden border-none bg-gradient-to-r from-teal-500 to-teal-600 text-white shadow-lg">
      {/* Decorative element */}
      <div className="pointer-events-none absolute -right-8 -top-8 h-32 w-32 rounded-full bg-white/10" />
      <div className="pointer-events-none absolute -right-4 bottom-0 h-20 w-20 rounded-full bg-white/5" />
      <CardContent className="relative py-6">
        <div className="flex items-start justify-between">
          <div>
            <p className="text-sm font-medium text-teal-100">{getGreeting()}</p>
            <h2 className="mt-0.5 text-2xl font-semibold tracking-tight">{name}</h2>
            <p className="mt-1.5 text-sm text-teal-100/80">{today}</p>
          </div>
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-white/15 backdrop-blur-sm">
            <Sparkles className="h-5 w-5 text-white" />
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
