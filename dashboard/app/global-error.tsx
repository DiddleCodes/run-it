"use client";

import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";

// Task 36: root-level boundary for errors that escape the root layout
// itself (app/error.tsx only catches errors below it). Per Next.js's own
// docs, global-error renders its own <html>/<body> and does not include
// the app's global styles/fonts, so this stays deliberately plain.
export default function GlobalError({ error, retry }: { error: Error & { digest?: string }; retry: () => void }) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);

  return (
    <html>
      <body
        style={{
          fontFamily: "-apple-system, Helvetica, Arial, sans-serif",
          background: "#0d0a0e",
          color: "#fff",
          minHeight: "100vh",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <div style={{ textAlign: "center", padding: 24 }}>
          <h2 style={{ margin: "0 0 12px", fontSize: 20, fontWeight: 600 }}>Something went wrong</h2>
          <p style={{ margin: "0 0 20px", fontSize: 14, color: "rgba(255,255,255,0.6)" }}>
            This has been reported. Try again, or reload the page.
          </p>
          <button
            onClick={() => retry()}
            style={{
              padding: "10px 24px",
              borderRadius: 8,
              background: "#7A1636",
              color: "#fff",
              border: "none",
              fontSize: 14,
              fontWeight: 600,
              cursor: "pointer",
            }}
          >
            Try again
          </button>
        </div>
      </body>
    </html>
  );
}
