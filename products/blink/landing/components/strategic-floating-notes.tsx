"use client"

import { useState, useEffect, useRef } from "react"
import { Card } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { X, Keyboard, MousePointer, Layers, Zap, Eye, Settings } from "lucide-react"

interface StrategicNote {
  id: string
  title: string
  content: string
  x: number
  y: number
  isCollapsed: boolean
  color: string
  icon: any
  delay: number
  section: string
}

export default function StrategicFloatingNotes() {
  const [notes, setNotes] = useState<StrategicNote[]>([
    {
      id: "shortcut-tip",
      title: "⌘ + H Shortcut",
      content:
        "This is your most powerful shortcut!\n\n• Instantly show/hide all notes\n• Works from any application\n• Perfect for presentations",
      x: 85,
      y: 15,
      isCollapsed: false,
      color: "bg-blue-50/90",
      icon: Keyboard,
      delay: 3000,
      section: "hero",
    },
    {
      id: "drag-demo",
      title: "Drag & Drop Magic",
      content:
        "Try dragging the notes above!\n\n• Smooth, responsive movement\n• Stays within bounds\n• Visual feedback on drag",
      x: 15,
      y: 60,
      isCollapsed: false,
      color: "bg-green-50/90",
      icon: MousePointer,
      delay: 8000,
      section: "features",
    },
  ])

  const [visibleNotes, setVisibleNotes] = useState<Set<string>>(new Set())
  const [dragState, setDragState] = useState<{
    isDragging: boolean
    noteId: string | null
    offset: { x: number; y: number }
    hasDragged: boolean
  }>({
    isDragging: false,
    noteId: null,
    offset: { x: 0, y: 0 },
    hasDragged: false,
  })
  const justDraggedRef = useRef(false)

  useEffect(() => {
    // Show notes with staggered delays
    notes.forEach((note) => {
      setTimeout(() => {
        setVisibleNotes((prev) => new Set([...prev, note.id]))
      }, note.delay)
    })

    // Auto-collapse some notes after showing
    setTimeout(() => {
      setNotes((prev) =>
        prev.map((note) =>
          note.id === "drag-demo" ? { ...note, isCollapsed: true } : note,
        ),
      )
    }, 12000)
  }, [])

  useEffect(() => {
    // Add global mouse event listeners for drag functionality
    const handleGlobalMouseMove = (e: MouseEvent) => {
      if (!dragState.isDragging || !dragState.noteId) return

      // Mark that we have dragged
      if (!dragState.hasDragged) {
        setDragState(prev => ({ ...prev, hasDragged: true }))
      }

      const newX = ((e.clientX - dragState.offset.x) / window.innerWidth) * 100
      const newY = ((e.clientY - dragState.offset.y) / window.innerHeight) * 100

      // Constrain to viewport bounds
      const constrainedX = Math.max(5, Math.min(95, newX))
      const constrainedY = Math.max(5, Math.min(95, newY))

      setNotes((prev) =>
        prev.map((note) => (note.id === dragState.noteId ? { ...note, x: constrainedX, y: constrainedY } : note)),
      )
    }

    const handleGlobalMouseUp = () => {
      const wasDragging = dragState.hasDragged
      justDraggedRef.current = wasDragging
      
      setDragState({
        isDragging: false,
        noteId: null,
        offset: { x: 0, y: 0 },
        hasDragged: false,
      })
      
      // Reset the flag after a brief delay to allow click events to be blocked
      if (wasDragging) {
        setTimeout(() => {
          justDraggedRef.current = false
        }, 50)
      }
    }

    if (dragState.isDragging) {
      document.addEventListener('mousemove', handleGlobalMouseMove)
      document.addEventListener('mouseup', handleGlobalMouseUp)
    }

    return () => {
      document.removeEventListener('mousemove', handleGlobalMouseMove)
      document.removeEventListener('mouseup', handleGlobalMouseUp)
    }
  }, [dragState])

  const handleMouseDown = (e: React.MouseEvent, noteId: string) => {
    e.preventDefault()
    e.stopPropagation()
    
    const note = notes.find((n) => n.id === noteId)
    if (!note) return

    // Calculate current position in pixels
    const noteX = (note.x / 100) * window.innerWidth
    const noteY = (note.y / 100) * window.innerHeight

    setDragState({
      isDragging: true,
      noteId,
      offset: {
        x: e.clientX - noteX,
        y: e.clientY - noteY,
      },
      hasDragged: false,
    })
  }


  const toggleNote = (id: string) => {
    if (dragState.isDragging || justDraggedRef.current) return // Don't toggle while dragging or just after drag
    setNotes((prev) => prev.map((note) => (note.id === id ? { ...note, isCollapsed: !note.isCollapsed } : note)))
  }

  const dismissNote = (id: string) => {
    setVisibleNotes((prev) => {
      const newSet = new Set(prev)
      newSet.delete(id)
      return newSet
    })
  }

  return (
    <div className="fixed inset-0 pointer-events-none z-50">
      {notes
        .filter((note) => visibleNotes.has(note.id))
        .map((note) => (
          <Card
            key={note.id}
            className={`absolute ${note.color} backdrop-blur-xl border border-white/40 shadow-xl pointer-events-auto animate-in fade-in slide-in-from-bottom-4 rounded-2xl ${
              dragState.isDragging && dragState.noteId === note.id
                ? "cursor-grabbing scale-110 shadow-2xl z-50"
                : "cursor-grab hover:scale-105 hover:shadow-2xl transition-all duration-500"
            }`}
            style={{
              left: `${note.x}%`,
              top: `${note.y}%`,
              width: note.isCollapsed ? "180px" : "220px",
              height: note.isCollapsed ? "44px" : "auto",
              transform: "translate(-50%, -50%)",
              zIndex: dragState.noteId === note.id ? 100 : 50,
            }}
            onMouseDown={(e) => handleMouseDown(e, note.id)}
            onClick={() => toggleNote(note.id)}
          >
            {/* Title bar */}
            <div className="flex items-center justify-between p-3 border-b border-white/30">
              <div className="flex items-center space-x-2">
                <note.icon className="w-4 h-4 text-slate-600" />
                <span className="font-text text-sm font-medium text-slate-700 truncate">{note.title}</span>
              </div>
              <div className="flex items-center space-x-1">
                <button
                  onClick={(e) => {
                    e.stopPropagation()
                    dismissNote(note.id)
                  }}
                  className="w-3 h-3 rounded-full bg-red-400/60 hover:bg-red-500 transition-colors flex items-center justify-center"
                >
                  <X className="w-2 h-2 text-white" />
                </button>
                <div className="w-3 h-3 rounded-full bg-yellow-400/60" />
                <div className="w-3 h-3 rounded-full bg-green-400/60" />
              </div>
            </div>

            {/* Content (hidden when collapsed) */}
            {!note.isCollapsed && (
              <div className="p-4">
                <pre className="font-text text-sm text-slate-700 whitespace-pre-wrap leading-relaxed">
                  {note.content}
                </pre>
              </div>
            )}

            {/* Floating indicator */}
            <div className="absolute -top-2 -right-2">
              <Badge variant="outline" className="border-white/50 text-slate-600 bg-white/80 text-xs px-2 py-1 rounded-xl">
                Tip
              </Badge>
            </div>
          </Card>
        ))}
    </div>
  )
}
