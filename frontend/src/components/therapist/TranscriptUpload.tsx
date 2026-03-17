import { useState, useCallback, useRef } from 'react'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import { Textarea } from '@/components/ui/textarea'
import { Label } from '@/components/ui/label'

interface TranscriptUploadProps {
  value: string
  onChange: (text: string) => void
}

export default function TranscriptUpload({ value, onChange }: TranscriptUploadProps) {
  const [isDragging, setIsDragging] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const lineCount = value ? value.split('\n').length : 0

  const handleFileRead = useCallback(
    (file: File) => {
      const reader = new FileReader()
      reader.onload = (e) => {
        const text = e.target?.result
        if (typeof text === 'string') {
          onChange(text)
        }
      }
      reader.readAsText(file)
    },
    [onChange],
  )

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault()
      setIsDragging(false)
      const file = e.dataTransfer.files[0]
      if (file && file.name.endsWith('.txt')) {
        handleFileRead(file)
      }
    },
    [handleFileRead],
  )

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(true)
  }, [])

  const handleDragLeave = useCallback(() => {
    setIsDragging(false)
  }, [])

  const handleFileChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0]
      if (file) {
        handleFileRead(file)
      }
    },
    [handleFileRead],
  )

  return (
    <div className="space-y-2">
      <Label>Session Transcript</Label>
      <Tabs defaultValue="paste">
        <TabsList>
          <TabsTrigger value="paste">Paste</TabsTrigger>
          <TabsTrigger value="upload">Upload</TabsTrigger>
        </TabsList>

        <TabsContent value="paste">
          <div className="space-y-1">
            <Textarea
              placeholder="Paste the session transcript here..."
              value={value}
              onChange={(e) => onChange(e.target.value)}
              className="min-h-[240px] font-mono text-sm"
              rows={12}
            />
            <p className="text-xs text-slate-500">
              {lineCount} {lineCount === 1 ? 'line' : 'lines'}
            </p>
          </div>
        </TabsContent>

        <TabsContent value="upload">
          <div
            className={`flex min-h-[240px] cursor-pointer flex-col items-center justify-center rounded-lg border-2 border-dashed transition-colors ${
              isDragging
                ? 'border-blue-400 bg-blue-50'
                : 'border-slate-300 bg-slate-50 hover:border-slate-400'
            }`}
            onDrop={handleDrop}
            onDragOver={handleDragOver}
            onDragLeave={handleDragLeave}
            onClick={() => fileInputRef.current?.click()}
          >
            <div className="text-center">
              <p className="text-sm font-medium text-slate-700">
                {isDragging ? 'Drop file here' : 'Drag and drop a .txt file'}
              </p>
              <p className="mt-1 text-xs text-slate-500">
                or click to browse
              </p>
            </div>
            <input
              ref={fileInputRef}
              type="file"
              accept=".txt"
              className="hidden"
              onChange={handleFileChange}
            />
          </div>
          {value && (
            <p className="mt-1 text-xs text-slate-500">
              File loaded: {lineCount} {lineCount === 1 ? 'line' : 'lines'}
            </p>
          )}
        </TabsContent>
      </Tabs>
    </div>
  )
}
