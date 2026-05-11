import ReactMarkdown, { type Components } from 'react-markdown'
import rehypeRaw from 'rehype-raw'
import rehypeSlug from 'rehype-slug'
import remarkGfm from 'remark-gfm'
import ArchDiagram from './blog/ArchDiagram'
import ContextExplorer from './blog/ContextExplorer'
import LatencyJourney from './blog/LatencyJourney'
import StatsRow from './blog/StatsRow'
import TestResults from './blog/TestResults'
import TurnPipeline from './blog/TurnPipeline'

const embeddedComponents = {
  ArchDiagram,
  ContextExplorer,
  LatencyJourney,
  StatsRow,
  TestResults,
  TurnPipeline,
}

const components: Components = {
  a({ href, children, ...props }) {
    const external = href?.startsWith('http')
    return (
      <a
        href={href}
        target={external ? '_blank' : undefined}
        rel={external ? 'noreferrer' : undefined}
        {...props}
      >
        {children}
      </a>
    )
  },
  div(props) {
    const componentName = (props as Record<string, unknown>)['data-mdx-component']

    if (typeof componentName === 'string' && componentName in embeddedComponents) {
      const Embedded = embeddedComponents[componentName as keyof typeof embeddedComponents]
      return <Embedded />
    }

    return <div {...props} />
  },
  img(props) {
    return <img loading="lazy" {...props} />
  },
}

interface MarkdownRendererProps {
  content: string
  className?: string
}

export function MarkdownRenderer({ content, className = 'markdown-body' }: MarkdownRendererProps) {
  return (
    <div className={className}>
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        rehypePlugins={[rehypeRaw, rehypeSlug]}
        components={components}
      >
        {content}
      </ReactMarkdown>
    </div>
  )
}
