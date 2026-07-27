import { StrictMode } from 'react';
import { renderToString } from 'react-dom/server';
import App from './App';

// Build-time prerender entry. Not used by the browser bundle — main.tsx
// still mounts with createRoot, so client behavior is unchanged.
export function render(_path: string): string {
  return renderToString(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}
