"use client"

import { useState } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Keyboard, Command, Eye, Layers, Zap, MousePointer, Settings } from "lucide-react"

interface Shortcut {
  keys: string[]
  description: string
  category: string
  icon: any
  example?: string
}

export default function KeyboardShortcutsGuide() {
  const [activeShortcut, setActiveShortcut] = useState<string | null>(null)

  const shortcuts: Shortcut[] = [
    // Global shortcuts
    {
      keys: ["⌘", "+", "N"],
      description: "Create new floating note",
      category: "global",
      icon: Command,
      example: "Opens a new note window instantly",
    },
    {
      keys: ["⌘", "+", "H"],
      description: "Show/hide all notes",
      category: "global",
      icon: Eye,
      example: "Toggle visibility of all floating notes",
    },
    {
      keys: ["⌘", "+", "⇧", "+", "H"],
      description: "Bring all notes to front",
      category: "global",
      icon: Layers,
      example: "Brings all notes above other windows",
    },
    {
      keys: ["⌘", "+", "⌥", "+", "H"],
      description: "Hide all notes temporarily",
      category: "global",
      icon: Eye,
      example: "Quick hide for presentations or focus",
    },

    // Individual note shortcuts
    {
      keys: ["⌘", "+", "1"],
      description: "Access note #1",
      category: "individual",
      icon: Zap,
      example: "Jump to your first pinned note",
    },
    {
      keys: ["⌘", "+", "2"],
      description: "Access note #2",
      category: "individual",
      icon: Zap,
      example: "Jump to your second pinned note",
    },
    {
      keys: ["⌘", "+", "3"],
      description: "Access note #3",
      category: "individual",
      icon: Zap,
      example: "Jump to your third pinned note",
    },
    {
      keys: ["⌘", "+", "9"],
      description: "Access last note",
      category: "individual",
      icon: Zap,
      example: "Jump to your most recent note",
    },

    // Note management
    {
      keys: ["⌘", "+", "W"],
      description: "Close current note",
      category: "management",
      icon: Command,
      example: "Close the focused note window",
    },
    {
      keys: ["⌘", "+", "D"],
      description: "Duplicate current note",
      category: "management",
      icon: Command,
      example: "Create a copy of the current note",
    },
    {
      keys: ["⌘", "+", "⇧", "+", "C"],
      description: "Collapse/expand note",
      category: "management",
      icon: Layers,
      example: "Toggle between full and title-bar view",
    },
    {
      keys: ["⌘", "+", "T"],
      description: "Toggle always on top",
      category: "management",
      icon: Eye,
      example: "Pin/unpin note above other windows",
    },

    // Mouse interactions
    {
      keys: ["Click"],
      description: "Focus note",
      category: "mouse",
      icon: MousePointer,
      example: "Bring note to front and focus",
    },
    {
      keys: ["Double", "Click"],
      description: "Collapse/expand note",
      category: "mouse",
      icon: MousePointer,
      example: "Toggle between full and collapsed view",
    },
    {
      keys: ["Middle", "Click"],
      description: "Quick actions menu",
      category: "mouse",
      icon: MousePointer,
      example: "Show context menu with options",
    },
    {
      keys: ["Drag"],
      description: "Move note position",
      category: "mouse",
      icon: MousePointer,
      example: "Reposition note anywhere on screen",
    },

    // System shortcuts
    {
      keys: ["⌘", "+", ","],
      description: "Open preferences",
      category: "system",
      icon: Settings,
      example: "Access app settings and customization",
    },
    {
      keys: ["⌘", "+", "Q"],
      description: "Quit application",
      category: "system",
      icon: Command,
      example: "Exit the floating notes app",
    },
  ]

  const categories = {
    global: { name: "Global Shortcuts", icon: Command, color: "bg-blue-50/80" },
    individual: { name: "Individual Notes", icon: Zap, color: "bg-green-50/80" },
    management: { name: "Note Management", icon: Layers, color: "bg-purple-50/80" },
    mouse: { name: "Mouse Interactions", icon: MousePointer, color: "bg-yellow-50/80" },
    system: { name: "System", icon: Settings, color: "bg-slate-50/80" },
  }

  const KeyboardKey = ({ keys, isActive = false }: { keys: string[]; isActive?: boolean }) => (
    <div className="flex items-center space-x-1">
      {keys.map((key, index) => (
        <span
          key={index}
          className={`inline-flex items-center justify-center min-w-[2.5rem] h-8 px-2 border rounded-xl shadow-sm font-mono text-sm font-medium transition-all duration-200 ${
            isActive
              ? "bg-slate-900 border-slate-700 text-white shadow-lg transform scale-105"
              : "bg-white border-slate-300 text-slate-700 hover:bg-slate-50"
          }`}
        >
          {key}
        </span>
      ))}
    </div>
  )

  return (
    <section id="shortcuts" className="py-32 px-4 bg-gradient-to-b from-white to-slate-50/50">
      <div className="max-w-7xl mx-auto">
        <div className="text-center mb-20">
          <Badge variant="outline" className="mb-6 border-slate-200 text-slate-600 bg-white/50 rounded-xl">
            <Keyboard className="w-3 h-3 mr-2" />
            Keyboard Shortcuts
          </Badge>
          <h2 className="font-display text-5xl md:text-6xl font-extralight text-slate-900 mb-6 leading-tight">
            Master Every Shortcut
          </h2>
          <p className="font-text text-xl text-slate-600 max-w-2xl mx-auto leading-relaxed">
            Become a power user with our comprehensive keyboard shortcuts. Every action is just a keystroke away.
          </p>
        </div>

        <Tabs defaultValue="all" className="w-full">
          <TabsList className="grid w-full grid-cols-6 mb-12 bg-white/50 backdrop-blur-sm">
            <TabsTrigger value="all" className="data-[state=active]:bg-white">
              All
            </TabsTrigger>
            <TabsTrigger value="global" className="data-[state=active]:bg-white">
              Global
            </TabsTrigger>
            <TabsTrigger value="individual" className="data-[state=active]:bg-white">
              Individual
            </TabsTrigger>
            <TabsTrigger value="management" className="data-[state=active]:bg-white">
              Management
            </TabsTrigger>
            <TabsTrigger value="mouse" className="data-[state=active]:bg-white">
              Mouse
            </TabsTrigger>
            <TabsTrigger value="system" className="data-[state=active]:bg-white">
              System
            </TabsTrigger>
          </TabsList>

          <TabsContent value="all" className="space-y-8">
            {Object.entries(categories).map(([categoryKey, category]) => (
              <div key={categoryKey}>
                <div className="flex items-center space-x-3 mb-6">
                  <category.icon className="w-6 h-6 text-slate-600" />
                  <h3 className="font-display text-2xl font-light text-slate-900">{category.name}</h3>
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  {shortcuts
                    .filter((shortcut) => shortcut.category === categoryKey)
                    .map((shortcut, index) => (
                      <Card
                        key={index}
                        className={`${category.color} backdrop-blur-xl border border-white/30 shadow-lg hover:shadow-xl transition-all duration-300 cursor-pointer ${
                          activeShortcut === `${categoryKey}-${index}` ? "ring-2 ring-slate-400" : ""
                        }`}
                        onClick={() =>
                          setActiveShortcut(
                            activeShortcut === `${categoryKey}-${index}` ? null : `${categoryKey}-${index}`,
                          )
                        }
                      >
                        <CardContent className="p-6">
                          <div className="flex items-center justify-between mb-4">
                            <KeyboardKey keys={shortcut.keys} isActive={activeShortcut === `${categoryKey}-${index}`} />
                            <shortcut.icon className="w-5 h-5 text-slate-500" />
                          </div>
                          <h4 className="font-text font-medium text-slate-900 mb-2">{shortcut.description}</h4>
                          {shortcut.example && (
                            <p className="font-text text-sm text-slate-600 leading-relaxed">{shortcut.example}</p>
                          )}
                        </CardContent>
                      </Card>
                    ))}
                </div>
              </div>
            ))}
          </TabsContent>

          {Object.entries(categories).map(([categoryKey, category]) => (
            <TabsContent key={categoryKey} value={categoryKey} className="space-y-6">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {shortcuts
                  .filter((shortcut) => shortcut.category === categoryKey)
                  .map((shortcut, index) => (
                    <Card
                      key={index}
                      className={`${category.color} backdrop-blur-xl border border-white/30 shadow-lg hover:shadow-xl transition-all duration-300 cursor-pointer ${
                        activeShortcut === `${categoryKey}-${index}` ? "ring-2 ring-slate-400" : ""
                      }`}
                      onClick={() =>
                        setActiveShortcut(
                          activeShortcut === `${categoryKey}-${index}` ? null : `${categoryKey}-${index}`,
                        )
                      }
                    >
                      <CardContent className="p-6">
                        <div className="flex items-center justify-between mb-4">
                          <KeyboardKey keys={shortcut.keys} isActive={activeShortcut === `${categoryKey}-${index}`} />
                          <shortcut.icon className="w-5 h-5 text-slate-500" />
                        </div>
                        <h4 className="font-text font-medium text-slate-900 mb-2">{shortcut.description}</h4>
                        {shortcut.example && (
                          <p className="font-text text-sm text-slate-600 leading-relaxed">{shortcut.example}</p>
                        )}
                      </CardContent>
                    </Card>
                  ))}
              </div>
            </TabsContent>
          ))}
        </Tabs>

        {/* Quick Reference Card */}
        <Card className="mt-16 bg-slate-900 border-slate-700 text-white rounded-2xl">
          <CardHeader>
            <CardTitle className="font-display text-xl font-light text-white flex items-center">
              <Zap className="w-5 h-5 mr-3" />
              Quick Reference
            </CardTitle>
          </CardHeader>
          <CardContent className="p-6">
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
              <div>
                <h4 className="font-text font-medium text-slate-300 mb-3">Most Used</h4>
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <KeyboardKey keys={["⌘", "+", "N"]} />
                    <span className="font-text text-sm text-slate-400">New note</span>
                  </div>
                  <div className="flex items-center justify-between">
                    <KeyboardKey keys={["⌘", "+", "H"]} />
                    <span className="font-text text-sm text-slate-400">Show/hide</span>
                  </div>
                </div>
              </div>
              <div>
                <h4 className="font-text font-medium text-slate-300 mb-3">Quick Access</h4>
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <KeyboardKey keys={["⌘", "+", "1"]} />
                    <span className="font-text text-sm text-slate-400">Note #1</span>
                  </div>
                  <div className="flex items-center justify-between">
                    <KeyboardKey keys={["⌘", "+", "2"]} />
                    <span className="font-text text-sm text-slate-400">Note #2</span>
                  </div>
                </div>
              </div>
              <div>
                <h4 className="font-text font-medium text-slate-300 mb-3">Management</h4>
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <KeyboardKey keys={["⌘", "+", "W"]} />
                    <span className="font-text text-sm text-slate-400">Close</span>
                  </div>
                  <div className="flex items-center justify-between">
                    <KeyboardKey keys={["⌘", "+", "D"]} />
                    <span className="font-text text-sm text-slate-400">Duplicate</span>
                  </div>
                </div>
              </div>
              <div>
                <h4 className="font-text font-medium text-slate-300 mb-3">Mouse</h4>
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="font-text text-sm text-white">Double Click</span>
                    <span className="font-text text-sm text-slate-400">Collapse</span>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="font-text text-sm text-white">Drag</span>
                    <span className="font-text text-sm text-slate-400">Move</span>
                  </div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Pro Tips */}
        <div className="mt-16 text-center">
          <h3 className="font-display text-2xl font-light text-slate-900 mb-8">Pro Tips</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <Card className="bg-blue-50/60 backdrop-blur-xl border border-blue-100/30 rounded-2xl">
              <CardContent className="p-6 text-center">
                <div className="w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center mx-auto mb-4">
                  <Keyboard className="w-6 h-6 text-blue-600" />
                </div>
                <h4 className="font-text font-medium text-slate-900 mb-2">Customize Shortcuts</h4>
                <p className="font-text text-sm text-slate-600">
                  Assign your own keyboard shortcuts to frequently used notes in preferences.
                </p>
              </CardContent>
            </Card>
            <Card className="bg-green-50/60 backdrop-blur-xl border border-green-100/30 rounded-2xl">
              <CardContent className="p-6 text-center">
                <div className="w-12 h-12 bg-green-100 rounded-lg flex items-center justify-center mx-auto mb-4">
                  <Zap className="w-6 h-6 text-green-600" />
                </div>
                <h4 className="font-text font-medium text-slate-900 mb-2">Muscle Memory</h4>
                <p className="font-text text-sm text-slate-600">
                  Practice the most common shortcuts daily to build muscle memory and increase speed.
                </p>
              </CardContent>
            </Card>
            <Card className="bg-purple-50/60 backdrop-blur-xl border border-purple-100/30 rounded-2xl">
              <CardContent className="p-6 text-center">
                <div className="w-12 h-12 bg-purple-100 rounded-lg flex items-center justify-center mx-auto mb-4">
                  <Command className="w-6 h-6 text-purple-600" />
                </div>
                <h4 className="font-text font-medium text-slate-900 mb-2">Workflow Integration</h4>
                <p className="font-text text-sm text-slate-600">
                  Combine shortcuts with your existing workflow for maximum productivity gains.
                </p>
              </CardContent>
            </Card>
          </div>
        </div>
      </div>
    </section>
  )
}
