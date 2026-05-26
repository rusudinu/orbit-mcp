import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Orbit MCP | Your Apple apps. Your AI. Your machine.",
  description:
    "Connect Apple Notes, Reminders, and Calendar to AI privately through local MCP servers.",
  icons: {
    icon: [
      { url: "/favicon.ico", sizes: "any" },
      { url: "/orbit-mcp-icon.png", type: "image/png", sizes: "1024x1024" },
    ],
    apple: [{ url: "/orbit-mcp-icon.png", sizes: "1024x1024" }],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
