import { useNavigate } from 'react-router-dom'
import type { ClientProfile } from '@/types'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'

interface ClientCardProps {
  client: ClientProfile
}

export default function ClientCard({ client }: ClientCardProps) {
  const navigate = useNavigate()

  return (
    <Card
      className="cursor-pointer transition-shadow hover:shadow-md"
      onClick={() => navigate(`/therapist/clients/${client.id}`)}
    >
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle className="text-slate-900">{client.name}</CardTitle>
          {client.has_safety_flags && (
            <Badge variant="destructive">Safety Flags</Badge>
          )}
        </div>
      </CardHeader>
      <CardContent>
        <div className="space-y-1 text-sm text-slate-600">
          <div className="flex justify-between">
            <span>Sessions</span>
            <span className="font-medium text-slate-900">
              {client.session_count ?? 0}
            </span>
          </div>
          <div className="flex justify-between">
            <span>Last session</span>
            <span className="font-medium text-slate-900">
              {client.last_session_date
                ? new Date(client.last_session_date).toLocaleDateString()
                : 'None'}
            </span>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
