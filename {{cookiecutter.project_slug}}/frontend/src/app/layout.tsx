import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "{{cookiecutter.project_name}}",
  description: "Django + Next.js Full-Stack Application",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ko">
      <body>{children}</body>
    </html>
  );
}
