import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

interface PlanSectionClientProps {
  icon: React.ReactNode
  title: string
  children: React.ReactNode
}

export default function PlanSectionClient({ icon, title, children }: PlanSectionClientProps) {
  return (
    <Card className="border-none shadow-sm bg-white/80 backdrop-blur-sm">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-teal-800">
          <span className="flex h-8 w-8 items-center justify-center rounded-full bg-teal-100 text-teal-600">
            {icon}
          </span>
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  )
}
