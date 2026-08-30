"use client"

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Progress } from "@/components/ui/progress"
import { useEffect, useState } from "react"
import { Activity, Database, Globe, Shield } from "lucide-react"

interface SystemMetric {
  name: string
  value: number
  unit: string
  status: "optimal" | "warning" | "critical"
  icon: any
}

export default function RealTimeMetrics() {
  const [metrics, setMetrics] = useState<SystemMetric[]>([
    { name: "System Load", value: 67, unit: "%", status: "optimal", icon: Activity },
    { name: "Memory Usage", value: 84, unit: "%", status: "warning", icon: Database },
    { name: "Network Health", value: 95, unit: "%", status: "optimal", icon: Globe },
    { name: "Security Status", value: 100, unit: "%", status: "optimal", icon: Shield },
  ])

  const [events, setEvents] = useState<Array<{ timestamp: string; type: string; message: string }>>([])

  useEffect(() => {
    // Smooth metric updates
    const metricsInterval = setInterval(() => {
      setMetrics((prev) =>
        prev.map((metric) => ({
          ...metric,
          value: Math.max(0, Math.min(100, metric.value + (Math.random() - 0.5) * 5)),
          status: metric.value > 90 ? "optimal" : metric.value > 75 ? "warning" : "critical",
        })),
      )
    }, 4000)

    // System events
    const eventMessages = [
      "System optimization complete",
      "Cache refresh successful",
      "Global sync established",
      "Security scan passed",
      "Performance boost applied",
      "Connection pool optimized",
    ]

    const eventsInterval = setInterval(() => {
      const newEvent = {
        timestamp: new Date().toLocaleTimeString(),
        type: Math.random() > 0.8 ? "warning" : "info",
        message: eventMessages[Math.floor(Math.random() * eventMessages.length)],
      }

      setEvents((prev) => [newEvent, ...prev.slice(0, 7)])
    }, 5000)

    return () => {
      clearInterval(metricsInterval)
      clearInterval(eventsInterval)
    }
  }, [])

  const getStatusColor = (status: string) => {
    switch (status) {
      case "optimal":
        return "text-green-400"
      case "warning":
        return "text-yellow-400"
      case "critical":
        return "text-red-400"
      default:
        return "text-white/60"
    }
  }

  return (
    <section className="py-32 px-4 bg-gradient-to-b from-gray-950 to-black">
      <div className="max-w-7xl mx-auto">
        <div className="text-center mb-20">
          <Badge variant="outline" className="mb-6 border-white/10 text-white/70 bg-white/5">
            System Health
          </Badge>
          <h2 className="font-display text-5xl md:text-6xl font-extralight text-white mb-6 leading-tight">Always On</h2>
          <p className="font-text text-xl text-white/60 max-w-2xl mx-auto leading-relaxed">
            Monitor everything that matters. Our platform keeps you informed with elegant, real-time insights into
            system performance.
          </p>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          {/* System Metrics */}
          <div className="lg:col-span-2 space-y-6">
            <Card className="bg-white/5 border-white/10 backdrop-blur-xl">
              <CardHeader>
                <CardTitle className="font-display text-xl font-light text-white">System Status</CardTitle>
              </CardHeader>
              <CardContent className="space-y-8">
                {metrics.map((metric, index) => (
                  <div key={index} className="space-y-3">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center space-x-3">
                        <metric.icon className="w-4 h-4 text-white/40" />
                        <span className="font-text text-white/80">{metric.name}</span>
                      </div>
                      <div className="flex items-center space-x-3">
                        <span className={`font-text text-lg ${getStatusColor(metric.status)}`}>
                          {metric.value.toFixed(0)}
                          {metric.unit}
                        </span>
                        <Badge
                          variant="outline"
                          className={`text-xs ${
                            metric.status === "optimal"
                              ? "border-green-500/30 text-green-400 bg-green-500/10"
                              : metric.status === "warning"
                                ? "border-yellow-500/30 text-yellow-400 bg-yellow-500/10"
                                : "border-red-500/30 text-red-400 bg-red-500/10"
                          }`}
                        >
                          {metric.status}
                        </Badge>
                      </div>
                    </div>
                    <Progress value={metric.value} className="h-1.5" />
                  </div>
                ))}
              </CardContent>
            </Card>

            {/* Global Status */}
            <Card className="bg-white/5 border-white/10 backdrop-blur-xl">
              <CardHeader>
                <CardTitle className="font-display text-xl font-light text-white">Global Infrastructure</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-6">
                  {[
                    { region: "Americas", latency: "12ms", status: "optimal" },
                    { region: "Europe", latency: "8ms", status: "optimal" },
                    { region: "Asia Pacific", latency: "15ms", status: "optimal" },
                    { region: "Middle East", latency: "10ms", status: "optimal" },
                  ].map((region, index) => (
                    <div key={index} className="text-center p-4 bg-black/20 rounded-xl">
                      <div className="font-text text-sm text-white/60 mb-2">{region.region}</div>
                      <div className="font-display text-xl font-light text-white">{region.latency}</div>
                      <div className="w-2 h-2 rounded-full mx-auto mt-3 bg-green-400 animate-pulse" />
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          </div>

          {/* System Events */}
          <Card className="bg-white/5 border-white/10 backdrop-blur-xl">
            <CardHeader>
              <CardTitle className="font-display text-xl font-light text-white flex items-center justify-between">
                Activity
                <Badge variant="outline" className="border-white/10 text-white/70 bg-white/5">
                  Live
                </Badge>
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-4 max-h-96 overflow-y-auto">
                {events.map((event, index) => (
                  <div key={index} className="font-text text-sm bg-black/20 p-4 rounded-lg border-l-2 border-white/10">
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-white/50 text-xs">{event.timestamp}</span>
                      <Badge
                        variant="outline"
                        className={`text-xs ${
                          event.type === "warning"
                            ? "border-yellow-500/30 text-yellow-400 bg-yellow-500/10"
                            : "border-green-500/30 text-green-400 bg-green-500/10"
                        }`}
                      >
                        {event.type}
                      </Badge>
                    </div>
                    <div className="text-white/80">{event.message}</div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </section>
  )
}
