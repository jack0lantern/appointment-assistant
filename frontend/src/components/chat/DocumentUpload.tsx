import { useRef, useState } from 'react'
import { Upload, FileCheck, Loader2, FileText, X } from 'lucide-react'
import { Button } from '@/components/ui/button'

interface DocumentUploadProps {
  onUpload: (file: File, documentType?: string) => Promise<boolean>
  disabled?: boolean
}

const ACCEPTED_TYPES = '.jpg,.jpeg,.png,.pdf,.gif'

export default function DocumentUpload({ onUpload, disabled }: DocumentUploadProps) {
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [uploading, setUploading] = useState(false)
  const [uploaded, setUploaded] = useState(false)
  const [pendingFile, setPendingFile] = useState<File | null>(null)

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    setPendingFile(file)
    if (fileInputRef.current) fileInputRef.current.value = ''
  }

  const clearPendingFile = () => setPendingFile(null)

  const handleConfirmUpload = async () => {
    if (!pendingFile) return
    setUploading(true)
    try {
      const success = await onUpload(pendingFile, 'insurance_card')
      if (success) {
        setUploaded(true)
        setPendingFile(null)
      }
    } finally {
      setUploading(false)
    }
  }

  if (uploaded) {
    return (
      <div className="flex items-center gap-2 rounded-lg bg-green-50 px-3 py-2 text-xs text-green-700">
        <FileCheck className="h-4 w-4" />
        <span>Document uploaded and verified</span>
      </div>
    )
  }

  const pickerDisabled = disabled || uploading

  return (
    <div className="space-y-2 px-3 py-2">
      <input
        ref={fileInputRef}
        type="file"
        accept={ACCEPTED_TYPES}
        capture="environment"
        onChange={handleFileChange}
        className="hidden"
      />
      {pendingFile ? (
        <div
          className="flex flex-col gap-2 rounded-lg border border-slate-200 bg-slate-50 p-3"
          role="status"
          aria-live="polite"
        >
          <div className="flex items-center gap-2">
            <FileText className="h-4 w-4 shrink-0 text-slate-500" aria-hidden />
            <span className="min-w-0 flex-1 truncate text-xs font-medium text-slate-700" title={pendingFile.name}>
              {pendingFile.name}
            </span>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={clearPendingFile}
              disabled={pickerDisabled}
              className="h-8 gap-1 text-slate-600"
            >
              <X className="h-3.5 w-3.5" />
              Remove
            </Button>
            <Button
              type="button"
              size="sm"
              onClick={handleConfirmUpload}
              disabled={pickerDisabled}
              className="h-8 bg-teal-600 hover:bg-teal-700"
            >
              {uploading ? (
                <>
                  <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" />
                  Uploading…
                </>
              ) : (
                'Upload file'
              )}
            </Button>
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={() => fileInputRef.current?.click()}
              disabled={pickerDisabled}
              className="h-8 text-slate-600"
            >
              Choose different file
            </Button>
          </div>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => fileInputRef.current?.click()}
          disabled={pickerDisabled}
          className="flex w-full items-center justify-center gap-2 rounded-lg border-2 border-dashed
                     border-slate-300 bg-slate-50 px-4 py-3 text-xs font-medium text-slate-600
                     transition-colors hover:border-teal-300 hover:bg-teal-50 hover:text-teal-700
                     disabled:cursor-not-allowed disabled:opacity-50"
        >
          <Upload className="h-4 w-4" />
          <span>Upload insurance card or ID</span>
        </button>
      )}
    </div>
  )
}
