"use client"

import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { useState } from "react"

export default function HowItWorksSection() {
  const [activeStep, setActiveStep] = useState(0)

  const steps = [
    {
      number: "01",
      title: "Create Your Note",
      description: "Open a new floating note window with a simple keyboard shortcut or menu action.",
      visual: "bg-blue-50/80",
      content: "New Note Created ✨",
    },
    {
      number: "02",
      title: "Position Anywhere",
      description: "Drag your note to any position on screen. It stays exactly where you put it, always on top.",
      visual: "bg-green-50/80",
      content: "📍 Positioned Perfectly",
    },
    {
      number: "03",
      title: "Collapse to Save Space",
      description: "Click to collapse notes to just their title bar. Double-click or middle-click to expand again.",
      visual: "bg-purple-50/80",
      content: "Meeting Notes ▼",
    },
    {
      number: "04",
      title: "Access Instantly",
      description:
        "Use global shortcuts to bring any note to the front, or assign individual shortcuts for quick access.",
      visual: "bg-yellow-50/80",
      content: (
        <div className="flex items-center justify-center space-x-1">
          <span className="inline-flex items-center justify-center min-w-[1.5rem] h-6 px-1.5 bg-white border border-slate-300 rounded-xl shadow-sm font-mono text-xs font-medium text-slate-700">
            ⌘
          </span>
          <span className="inline-flex items-center justify-center min-w-[1.5rem] h-6 px-1.5 bg-white border border-slate-300 rounded-xl shadow-sm font-mono text-xs font-medium text-slate-700">
            +
          </span>
          <span className="inline-flex items-center justify-center min-w-[1.5rem] h-6 px-1.5 bg-white border border-slate-300 rounded-xl shadow-sm font-mono text-xs font-medium text-slate-700">
            H
          </span>
          <span className="text-slate-600 ml-2">→ Instant Access</span>
        </div>
      ),
    },
  ]

  return (
    <section className="py-32 px-4">
      <div className="max-w-7xl mx-auto">
        <div className="text-center mb-20">
          <Badge variant="outline" className="mb-6 border-slate-200 text-slate-600 bg-white/50 rounded-xl">
            How It Works
          </Badge>
          <h2 className="font-display text-5xl md:text-6xl font-extralight text-slate-900 mb-6 leading-tight">
            Simple by Design
          </h2>
          <p className="font-text text-xl text-slate-600 max-w-2xl mx-auto leading-relaxed">
            Four simple steps to transform how you work with notes. No learning curve, just pure productivity.
          </p>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 items-center">
          {/* Steps */}
          <div className="space-y-6">
            {steps.map((step, index) => (
              <Card
                key={index}
                className={`cursor-pointer transition-all duration-300 rounded-2xl ${
                  activeStep === index
                    ? "bg-white shadow-xl border-slate-300"
                    : "bg-white/40 hover:bg-white/60 border-slate-200"
                }`}
                onClick={() => setActiveStep(index)}
              >
                <CardContent className="p-6">
                  <div className="flex items-start space-x-4">
                    <div
                      className={`font-display text-2xl font-light ${
                        activeStep === index ? "text-slate-900" : "text-slate-400"
                      }`}
                    >
                      {step.number}
                    </div>
                    <div className="flex-1">
                      <h3
                        className={`font-display text-xl font-medium mb-2 ${
                          activeStep === index ? "text-slate-900" : "text-slate-600"
                        }`}
                      >
                        {step.title}
                      </h3>
                      <p
                        className={`font-text leading-relaxed ${
                          activeStep === index ? "text-slate-600" : "text-slate-500"
                        }`}
                      >
                        {step.description}
                      </p>
                    </div>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>

          {/* Visual Demo */}
          <div className="relative">
            <div className="bg-gradient-to-br from-slate-100/50 to-blue-50/30 rounded-3xl border border-slate-200/50 h-96 flex items-center justify-center overflow-hidden">
              <Card
                className={`${steps[activeStep].visual} backdrop-blur-xl border border-white/30 shadow-xl transition-all duration-500 transform hover:scale-105 rounded-2xl`}
              >
                <CardContent className="p-6 text-center">
                  <div className="font-text text-slate-700 text-lg">
                    {typeof steps[activeStep].content === "string"
                      ? steps[activeStep].content
                      : steps[activeStep].content}
                  </div>
                </CardContent>
              </Card>

              {/* Floating decoration */}
              <div className="absolute top-8 right-8 w-16 h-8 bg-white/40 backdrop-blur-xl rounded-lg border border-white/20 opacity-60" />
              <div className="absolute bottom-12 left-8 w-20 h-6 bg-blue-50/60 backdrop-blur-xl rounded-lg border border-blue-100/20 opacity-40" />
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
