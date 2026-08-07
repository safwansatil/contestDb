import { Component, type ReactNode } from 'react'

export class ErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null }
  static getDerivedStateFromError(error: Error) { return { error } }
  componentDidCatch(error: Error) { console.error('[ErrorBoundary]', error) }
  render() {
    if (this.state.error) {
      return (
        <div style={{ maxWidth: 720, margin: '80px auto', padding: 24 }} className="glass pad-lg">
          <h2 style={{ color: 'var(--wa)' }}>Something broke while rendering</h2>
          <pre className="mono" style={{ whiteSpace: 'pre-wrap', fontSize: 12, color: 'var(--ink-dim)', marginTop: 12 }}>
            {this.state.error.message}
            {'\n\n'}
            {this.state.error.stack}
          </pre>
          <button className="btn primary" style={{ marginTop: 16 }} onClick={() => location.reload()}>Reload</button>
        </div>
      )
    }
    return this.props.children
  }
}
