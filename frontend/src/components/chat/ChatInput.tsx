import { useState, useRef, type KeyboardEvent } from 'react'
import { Button } from '@/components/ui/button'
import { SendHorizonal, Paperclip, Camera } from 'lucide-react'

const ACCEPTED_FILE_TYPES = '.jpg,.jpeg,.png,.pdf,.gif'

interface ChatInputProps {
  onSend: (text: string) => void
  onUpload?: (file: File, documentType?: string) => Promise<void>
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
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const cameraInputRef = useRef<HTMLInputElement>(null)

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

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file || !onUpload) return

    setUploading(true)
    try {
      await onUpload(file)
    } finally {
      setUploading(false)
      e.target.value = ''
    }
  }

  const isDisabled = disabled || uploading

  return (
    <div className="flex items-end gap-2 border-t bg-white p-3">
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
          <input
            ref={cameraInputRef}
            type="file"
            accept="image/*"
            capture="environment"
            onChange={handleFileChange}
            className="hidden"
            aria-label="Take photo"
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
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={() => cameraInputRef.current?.click()}
              disabled={isDisabled}
              className="h-9 w-9 rounded-full p-0 text-slate-500 hover:bg-slate-100 hover:text-slate-700"
              aria-label="Take photo"
            >
              <Camera className="h-4 w-4" />
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
  )
}
