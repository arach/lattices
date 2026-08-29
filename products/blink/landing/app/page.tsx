"use client"

import { TopBar } from "@/components/homepage/Chrome"
import Hero from "@/components/homepage/Hero"
import { SpecStrip } from "@/components/homepage/Architecture"
import Sheets from "@/components/homepage/Sheets"
import FilesystemAPI from "@/components/homepage/FilesystemAPI"
import AgentGuide from "@/components/homepage/AgentGuide"
import AgentCaseStudy, { AgentFilm } from "@/components/homepage/AgentCaseStudy"
import Keys from "@/components/homepage/Keys"
import { Install, Footer } from "@/components/homepage/Install"

export default function Home() {
  return (
    <div className="crt min-h-screen">
      <TopBar />
      <main>
        <Hero />
        <SpecStrip />
        <AgentFilm />
        <FilesystemAPI />
        <AgentGuide />
        <AgentCaseStudy />
        <Sheets />
        <Keys />
        <Install />
      </main>
      <Footer />
    </div>
  )
}
