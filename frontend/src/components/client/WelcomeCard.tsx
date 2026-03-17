import { Card, CardContent } from '@/components/ui/card'

interface WelcomeCardProps {
  name: string
}

export default function WelcomeCard({ name }: WelcomeCardProps) {
  const today = new Date().toLocaleDateString('en-US', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  })

  return (
    <Card className="border-none bg-gradient-to-r from-teal-500 to-teal-600 text-white shadow-lg">
      <CardContent className="py-6">
        <h2 className="text-2xl font-semibold tracking-tight">
          Welcome back, {name}
        </h2>
        <p className="mt-1 text-teal-100 text-sm">{today}</p>
      </CardContent>
    </Card>
  )
}
