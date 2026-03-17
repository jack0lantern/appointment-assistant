import ReactDiffViewer from 'react-diff-viewer-continued'

interface DiffSection {
  status: 'unchanged' | 'modified' | 'added' | 'removed'
  old_text: string
  new_text: string
}

interface VersionDiffProps {
  version1: number
  version2: number
  diffs: Record<string, DiffSection>
}

function toTitleCase(key: string): string {
  return key
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (char) => char.toUpperCase())
}

export default function VersionDiff({ version1, version2, diffs }: VersionDiffProps) {
  const changedSections = Object.entries(diffs).filter(
    ([, section]) => section.status !== 'unchanged'
  )

  return (
    <div className="space-y-6">
      <h3 className="text-base font-semibold text-slate-800">
        v{version1} &rarr; v{version2}
      </h3>

      {changedSections.length === 0 ? (
        <p className="text-sm text-slate-500 text-center py-6">
          No differences between these versions.
        </p>
      ) : (
        changedSections.map(([key, section]) => (
          <div key={key}>
            <p className="text-sm font-medium text-slate-700 mb-2">
              {toTitleCase(key)}
            </p>
            <ReactDiffViewer
              oldValue={section.old_text}
              newValue={section.new_text}
              splitView={false}
            />
          </div>
        ))
      )}
    </div>
  )
}
