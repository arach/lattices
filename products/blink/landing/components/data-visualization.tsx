"use client"

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { useEffect, useState } from "react"

export default function DataVisualization() {
  const [dataPoints, setDataPoints] = useState<number[]>([])
  const [networkNodes, setNetworkNodes] = useState<Array<{ x: number; y: number; active: boolean }>>([])

  useEffect(() => {
    // Generate smooth data points
    const points = Array.from({ length: 60 }, (_, i) => Math.sin(i * 0.15) * 25 + Math.random() * 10 + 50)
    setDataPoints(points)

    // Generate network nodes
    const nodes = Array.from({ length: 15 }, () => ({
      x: Math.random() * 400,
      y: Math.random() * 300,
      active: Math.random() > 0.2,
    }))
    setNetworkNodes(nodes)

    // Smooth updates
    const interval = setInterval(() => {
      setDataPoints((prev) => {
        const newPoints = [...prev.slice(1)]
        newPoints.push(Math.sin(newPoints.length * 0.15) * 25 + Math.random() * 10 + 50)
        return newPoints
      })

      setNetworkNodes((prev) =>
        prev.map((node) => ({
          ...node,
          active: Math.random() > 0.15,
        })),
      )
    }, 2000)

    return () => clearInterval(interval)
  }, [])

  return (
    <section className="py-32 px-4">
      <div className="max-w-7xl mx-auto">
        <div className="text-center mb-20">
          <Badge variant="outline" className="mb-6 border-white/10 text-white/70 bg-white/5">
            Live Analytics
          </Badge>
          <h2 className="font-display text-5xl md:text-6xl font-extralight text-white mb-6 leading-tight">
            See Everything
          </h2>
          <p className="font-text text-xl text-white/60 max-w-2xl mx-auto leading-relaxed">
            Beautiful visualizations that make complex data simple. Understand your business at a glance with
            intelligent insights.
          </p>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
          {/* Performance Chart */}
          <Card className="bg-white/5 border-white/10 backdrop-blur-xl">
            <CardHeader>
              <CardTitle className="font-display text-xl font-light text-white flex items-center justify-between">
                Performance Metrics
                <Badge variant="outline" className="border-green-500/30 text-green-400 bg-green-500/10">
                  Live
                </Badge>
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="h-64 relative bg-black/20 rounded-xl p-6 overflow-hidden">
                <svg width="100%" height="100%" className="absolute inset-0">
                  <defs>
                    <linearGradient id="gradient" x1="0%" y1="0%" x2="0%" y2="100%">
                      <stop offset="0%" stopColor="#ffffff" stopOpacity="0.6" />
                      <stop offset="100%" stopColor="#ffffff" stopOpacity="0.05" />
                    </linearGradient>
                  </defs>
                  <polyline
                    fill="none"
                    stroke="#ffffff"
                    strokeWidth="1.5"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    points={dataPoints
                      .map((point, index) => `${(index / dataPoints.length) * 100}%,${100 - (point / 100) * 100}%`)
                      .join(" ")}
                  />
                  <polyline
                    fill="url(#gradient)"
                    stroke="none"
                    points={`0,100% ${dataPoints
                      .map((point, index) => `${(index / dataPoints.length) * 100}%,${100 - (point / 100) * 100}%`)
                      .join(" ")} 100%,100%`}
                  />
                </svg>

                <div className="absolute top-6 left-6 font-text text-xs text-white/50">
                  <div>Peak: {Math.max(...dataPoints).toFixed(1)}ms</div>
                  <div>Average: {(dataPoints.reduce((a, b) => a + b, 0) / dataPoints.length).toFixed(1)}ms</div>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Network Status */}
          <Card className="bg-white/5 border-white/10 backdrop-blur-xl">
            <CardHeader>
              <CardTitle className="font-display text-xl font-light text-white flex items-center justify-between">
                Global Network
                <Badge variant="outline" className="border-blue-500/30 text-blue-400 bg-blue-500/10">
                  {networkNodes.filter((n) => n.active).length} Online
                </Badge>
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="h-64 relative bg-black/20 rounded-xl overflow-hidden">
                <svg width="100%" height="100%" className="absolute inset-0">
                  {/* Connection lines */}
                  {networkNodes.map((node, i) =>
                    networkNodes.slice(i + 1).map((otherNode, j) => {
                      const distance = Math.sqrt(Math.pow(node.x - otherNode.x, 2) + Math.pow(node.y - otherNode.y, 2))
                      if (distance < 120 && node.active && otherNode.active) {
                        return (
                          <line
                            key={`${i}-${j}`}
                            x1={`${(node.x / 400) * 100}%`}
                            y1={`${(node.y / 300) * 100}%`}
                            x2={`${(otherNode.x / 400) * 100}%`}
                            y2={`${(otherNode.y / 300) * 100}%`}
                            stroke="#ffffff"
                            strokeWidth="0.5"
                            opacity="0.2"
                          />
                        )
                      }
                      return null
                    }),
                  )}

                  {/* Nodes */}
                  {networkNodes.map((node, i) => (
                    <circle
                      key={i}
                      cx={`${(node.x / 400) * 100}%`}
                      cy={`${(node.y / 300) * 100}%`}
                      r={node.active ? "3" : "1.5"}
                      fill={node.active ? "#ffffff" : "#ffffff40"}
                      className={node.active ? "animate-pulse" : ""}
                    />
                  ))}
                </svg>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Key Metrics */}
        <div className="mt-16 grid grid-cols-2 md:grid-cols-4 gap-8">
          {[
            { label: "Operations", value: "2.4M/sec", color: "text-white" },
            { label: "Bandwidth", value: "847 GB/s", color: "text-white" },
            { label: "Efficiency", value: "99.7%", color: "text-white" },
            { label: "Latency", value: "12ms", color: "text-white" },
          ].map((metric, index) => (
            <div key={index} className="text-center">
              <div className={`font-display text-3xl font-light ${metric.color} mb-2`}>{metric.value}</div>
              <div className="font-text text-sm text-white/50 uppercase tracking-wider">{metric.label}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
