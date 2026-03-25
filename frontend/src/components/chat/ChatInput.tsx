import { useState, useRef, type KeyboardEvent } from 'react'
import { Button } from '@/components/ui/button'
import { SendHorizonal, Paperclip, FileText, X, Loader2 } from 'lucide-react'
import { MAX_CHAT_MESSAGE_CHARS } from '@/lib/chatLimits'

const ACCEPTED_FILE_TYPES = '.jpg,.jpeg,.png,.pdf,.gif'

interface ChatInputProps {
  onSend: (text: string) => void
  onUpload?: (file: File, documentType?: string) => Promise<boolean>
  disabled?: boolean
  placeholder?: string
}

export default function ChatInput({
  onSend,
  onUpload,
  disabled = false,
  placeholder = 'Type a message...',
}: ChatInputProps) {
  const [value, setValue] = useState('')
  const [uploading, setUploading] = useState(false)
  const [pendingFile, setPendingFile] = useState<File | null>(null)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const handleSend = () => {
    const trimmed = value.trim()
    if (!trimmed || disabled || uploading) return
    onSend(trimmed)
    setValue('')
    textareaRef.current?.focus()
  }

  const handleKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file || !onUpload) return
    setPendingFile(file)
    e.target.value = ''
  }

  const clearPendingFile = () => setPendingFile(null)

  const handleConfirmUpload = async () => {
    if (!pendingFile || !onUpload) return
    setUploading(true)
    try {
      const success = await onUpload(pendingFile)
      if (success) setPendingFile(null)
    } finally {
      setUploading(false)
    }
  }

  const isDisabled = disabled || uploading

  return (
    <div className="border-t bg-white">
      {onUpload && pendingFile && (
        <div
          className="flex items-center gap-2 border-b border-slate-100 bg-slate-50 px-3 py-2"
          role="status"
          aria-live="polite"
        >
          <FileText className="h-4 w-4 shrink-0 text-slate-500" aria-hidden />
          <span className="min-w-0 flex-1 truncate text-sm text-slate-700" title={pendingFile.name}>
            {pendingFile.name}
          </span>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={clearPendingFile}
            disabled={isDisabled}
            className="h-8 shrink-0 gap-1 px-2 text-slate-600"
            aria-label="Remove attached file"
          >
            <X className="h-4 w-4" />
            Remove
          </Button>
          <Button
            type="button"
            size="sm"
            onClick={handleConfirmUpload}
            disabled={isDisabled}
            className="h-8 shrink-0 gap-1 bg-teal-600 hover:bg-teal-700"
          >
            {uploading ? (
              <>
                <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden />
                Sending…
              </>
            ) : (
              'Send file'
            )}
          </Button>
        </div>
      )}
      <div className="flex items-end gap-2 p-3">
        {onUpload && (
          <>
            <input
              ref={fileInputRef}
              type="file"
              accept={ACCEPTED_FILE_TYPES}
              onChange={handleFileChange}
              className="hidden"
              aria-label="Attach file"
            />
            <div className="flex shrink-0 gap-1">
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => fileInputRef.current?.click()}
                disabled={isDisabled}
                className="h-9 w-9 rounded-full p-0 text-slate-500 hover:bg-slate-100 hover:text-slate-700"
                aria-label="Attach file"
              >
                <Paperclip className="h-4 w-4" />
              </Button>
            </div>
          </>
        )}
        <textarea
          ref={textareaRef}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder={placeholder}
          disabled={isDisabled}
          maxLength={MAX_CHAT_MESSAGE_CHARS}
          rows={1}
          className="flex-1 resize-none rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-sm
                     placeholder:text-slate-400 focus:border-teal-400 focus:outline-none focus:ring-1 focus:ring-teal-400
                     disabled:opacity-50"
          style={{ maxHeight: '120px' }}
        />
        <Button
          size="sm"
          onClick={handleSend}
          disabled={isDisabled || !value.trim()}
          className="h-9 w-9 shrink-0 rounded-full bg-teal-600 p-0 hover:bg-teal-700"
        >
          <SendHorizonal className="h-4 w-4" />
        </Button>
      </div>
    </div>
  )
}
