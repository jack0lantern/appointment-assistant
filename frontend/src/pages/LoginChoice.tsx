import { Link } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { buttonVariants } from '@/components/ui/button'
import { cn } from '@/lib/utils'

export default function LoginChoice() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-slate-50">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">Appointment Assistant</CardTitle>
          <p className="text-sm text-muted-foreground">Choose your login</p>
        </CardHeader>
        <CardContent className="space-y-3">
          <Link
            to="/login/client"
            className={cn(buttonVariants({ variant: 'outline' }), 'w-full h-14 text-base flex items-center justify-center')}
          >
            I'm a client
          </Link>
          <Link
            to="/login/therapist"
            className={cn(buttonVariants({ variant: 'outline' }), 'w-full h-14 text-base flex items-center justify-center')}
          >
            I'm a therapist
          </Link>
        </CardContent>
      </Card>
    </div>
  )
}
