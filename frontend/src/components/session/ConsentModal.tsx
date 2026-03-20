import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'

interface ConsentModalProps {
  open: boolean
  onAccept: () => void
  onDecline: () => void
  isTherapist: boolean
}

export default function ConsentModal({ open, onAccept, onDecline, isTherapist }: ConsentModalProps) {
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onDecline()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Recording Consent</DialogTitle>
          <DialogDescription>
            {isTherapist
              ? 'You are about to start recording this therapy session. Both you and your client must consent. The recording will be used to generate a session transcript for treatment planning.'
              : 'Your therapist has requested to record this session. The recording will be used to generate a session transcript for treatment planning purposes.'}
          </DialogDescription>
        </DialogHeader>
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800">
          <strong>Notice:</strong> Recording will capture audio from all participants.
          Both participants will see a recording indicator while recording is active.
          Either participant can stop recording at any time.
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onDecline}>
            Decline
          </Button>
          <Button onClick={onAccept}>
            I Consent to Recording
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
