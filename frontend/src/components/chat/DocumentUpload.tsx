import { useRef, useState } from 'react'
import { Upload, FileCheck, Loader2 } from 'lucide-react'

interface DocumentUploadProps {
  onUpload: (file: File, documentType?: string) => Promise<void>
  disabled?: boolean
}

const ACCEPTED_TYPES = '.jpg,.jpeg,.png,.pdf,.gif'

export default function DocumentUpload({ onUpload, disabled }: DocumentUploadProps) {
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [uploading, setUploading] = useState(false)
  const [uploaded, setUploaded] = useState(false)

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    setUploading(true)
    try {
      await onUpload(file, 'insurance_card')
      setUploaded(true)
    } finally {
      setUploading(false)
      if (fileInputRef.current) fileInputRef.current.value = ''
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

  return (
    <div className="px-3 py-2">
      <input
        ref={fileInputRef}
        type="file"
        accept={ACCEPTED_TYPES}
        capture="environment"
        onChange={handleFileChange}
        className="hidden"
      />
      <button
        onClick={() => fileInputRef.current?.click()}
        disabled={disabled || uploading}
        className="flex w-full items-center justify-center gap-2 rounded-lg border-2 border-dashed
                   border-slate-300 bg-slate-50 px-4 py-3 text-xs font-medium text-slate-600
                   transition-colors hover:border-teal-300 hover:bg-teal-50 hover:text-teal-700
                   disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {uploading ? (
          <>
            <Loader2 className="h-4 w-4 animate-spin" />
            <span>Uploading...</span>
          </>
        ) : (
          <>
            <Upload className="h-4 w-4" />
            <span>Upload insurance card or ID</span>
          </>
        )}
      </button>
    </div>
  )
}
