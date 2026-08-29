"use client"

import type React from "react"

import { useState, useEffect, useRef } from "react"
import { Card } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"

interface FloatingNote {
  id: string
  title: string
  content: string
  x: number
  y: number
  isCollapsed: boolean
  color: string
}

export default function FloatingNotesDemo() {
  const [notes, setNotes] = useState<FloatingNote[]>([
    {
      id: "1",
      title: "Meeting Notes",
      content: "• Discuss Q4 roadmap\n• Review user feedback\n• Plan next sprint",
      x: 10,
      y: 20,
      isCollapsed: false,
      color: "bg-white/80",
    },
    {
      id: "2",
      title: "Quick Ideas",
      content: "New feature: Dark mode\nImprove onboarding flow\nAdd keyboard shortcuts guide",
      x: 60,
      y: 40,
      isCollapsed: true,
      color: "bg-blue-50/90",
    },
    {
      id: "3",
      title: "Shopping List",
      content: "🥛 Milk\n🍞 Bread\n🥑 Avocados\n☕ Coffee beans",
      x: 20,
      y: 70,
      isCollapsed: false,
      color: "bg-green-50/80",
    },
  ])

  const [dragState, setDragState] = useState<{
    isDragging: boolean
    noteId: string | null
    offset: { x: number; y: number }
  }>({
    isDragging: false,
    noteId: null,
    offset: { x: 0, y: 0 },
  })

  const containerRef = useRef<HTMLDivElement>(null)

  const handleMouseDown = (e: React.MouseEvent, noteId: string) => {
    if (!containerRef.current) return

    const rect = containerRef.current.getBoundingClientRect()
    const note = notes.find((n) => n.id === noteId)
    if (!note) return

    const noteX = (note.x / 100) * rect.width
    const noteY = (note.y / 100) * rect.height

    setDragState({
      isDragging: true,
      noteId,
      offset: {
        x: e.clientX - rect.left - noteX,
        y: e.clientY - rect.top - noteY,
      },
    })
  }

  const handleMouseMove = (e: React.MouseEvent) => {
    if (!dragState.isDragging || !dragState.noteId || !containerRef.current) return

    const rect = containerRef.current.getBoundingClientRect()
    const newX = ((e.clientX - rect.left - dragState.offset.x) / rect.width) * 100
    const newY = ((e.clientY - rect.top - dragState.offset.y) / rect.height) * 100

    // Constrain to container bounds
    const constrainedX = Math.max(0, Math.min(75, newX))
    const constrainedY = Math.max(0, Math.min(80, newY))

    setNotes((prev) =>
      prev.map((note) => (note.id === dragState.noteId ? { ...note, x: constrainedX, y: constrainedY } : note)),
    )
  }

  const handleMouseUp = () => {
    setDragState({
      isDragging: false,
      noteId: null,
      offset: { x: 0, y: 0 },
    })
  }

  const toggleNote = (id: string) => {
    if (dragState.isDragging) return // Don't toggle while dragging
    setNotes((prev) => prev.map((note) => (note.id === id ? { ...note, isCollapsed: !note.isCollapsed } : note)))
  }

  useEffect(() => {
    // Auto-demo: collapse and expand notes (but not while dragging)
    const interval = setInterval(() => {
      if (dragState.isDragging) return

      setNotes((prev) => {
        const randomNote = prev[Math.floor(Math.random() * prev.length)]
        return prev.map((note) => (note.id === randomNote.id ? { ...note, isCollapsed: !note.isCollapsed } : note))
      })
    }, 4000)

    return () => clearInterval(interval)
  }, [dragState.isDragging])

  return (
    <section id="demo" className="py-32 px-4 relative">
      <div className="max-w-7xl mx-auto">
        <div className="text-center mb-20">
          <Badge variant="outline" className="mb-6 border-slate-200 text-slate-600 bg-white/50 rounded-xl">
            Interactive Demo
          </Badge>
          <h2 className="font-display text-5xl md:text-6xl font-extralight text-slate-900 mb-6 leading-tight">
            See It in Action
          </h2>
          <p className="font-text text-xl text-slate-600 max-w-2xl mx-auto leading-relaxed">
            Drag notes around, click to collapse/expand. Experience the fluid interactions that make floating notes so
            powerful.
          </p>
        </div>

        {/* Interactive floating notes */}
        <div
          ref={containerRef}
          className="relative h-96 bg-gradient-to-br from-slate-100/50 to-blue-50/30 rounded-3xl border border-slate-200/50 overflow-hidden select-none"
          onMouseMove={handleMouseMove}
          onMouseUp={handleMouseUp}
          onMouseLeave={handleMouseUp}
        >
          {notes.map((note) => (
            <Card
              key={note.id}
              className={`absolute ${note.color} backdrop-blur-xl border border-white/30 shadow-xl transition-all duration-200 rounded-2xl ${
                dragState.isDragging && dragState.noteId === note.id
                  ? "cursor-grabbing scale-105 shadow-2xl"
                  : "cursor-grab hover:shadow-2xl hover:scale-105"
              }`}
              style={{
                left: `${note.x}%`,
                top: `${note.y}%`,
                width: note.isCollapsed ? "200px" : "240px",
                height: note.isCollapsed ? "40px" : "auto",
                zIndex: dragState.noteId === note.id ? 10 : 1,
              }}
              onMouseDown={(e) => handleMouseDown(e, note.id)}
              onClick={() => toggleNote(note.id)}
            >
              {/* Title bar */}
              <div className="flex items-center justify-between p-3 border-b border-white/20">
                <span className="font-text text-sm font-medium text-slate-700 truncate">{note.title}</span>
                <div className="flex items-center space-x-1">
                  <div className="w-3 h-3 rounded-full bg-green-400 opacity-60" />
                  <div className="w-3 h-3 rounded-full bg-yellow-400 opacity-60" />
                  <div className="w-3 h-3 rounded-full bg-red-400 opacity-60" />
                </div>
              </div>

              {/* Content (hidden when collapsed) */}
              {!note.isCollapsed && (
                <div className="p-4">
                  <pre className="font-text text-sm text-slate-600 whitespace-pre-wrap leading-relaxed">
                    {note.content}
                  </pre>
                </div>
              )}
            </Card>
          ))}

          {/* Instruction overlay */}
          <div className="absolute bottom-4 left-4 right-4 text-center">
            <p className="font-text text-sm text-slate-500 bg-white/70 backdrop-blur-sm rounded-2xl px-4 py-2 inline-block">
              Drag notes around • Click to collapse/expand • Auto-demo running
            </p>
          </div>
        </div>
      </div>
    </section>
  )
}
