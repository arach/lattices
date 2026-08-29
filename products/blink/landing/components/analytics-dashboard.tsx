"use client"

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { TrendingUp, Activity, Users, Zap } from "lucide-react"
import { useEffect, useState } from "react"

interface MetricData {
  label: string
  value: string
  change: string
  trend: "up" | "down"
  icon: any
}

export default function AnalyticsDashboard() {
  const [metrics, setMetrics] = useState<MetricData[]>([
    { label: "Active Users", value: "2.4M", change: "+12%", trend: "up", icon: Users },
    { label: "Processing Speed", value: "847ms", change: "+5%", trend: "up", icon: Zap },
    { label: "Data Processed", value: "94.7TB", change: "+18%", trend: "up", icon: Activity },
    { label: "Success Rate", value: "99.97%", change: "+0.03%", trend: "up", icon: TrendingUp },
  ])

  useEffect(() => {
    const interval = setInterval(() => {
      setMetrics((prev) =>
        prev.map((metric) => ({
          ...metric,
          value: metric.label === "Processing Speed" ? `${(Math.random() * 100 + 800).toFixed(0)}ms` : metric.value,
        })),
      )
    }, 3000)

    return () => clearInterval(interval)
  }, [])

  return (
    <section className="py-32 px-4 bg-gradient-to-b from-black to-gray-950">
      <div className="max-w-7xl mx-auto">
        <div className="text-center mb-20">
          <Badge variant="outline" className="mb-6 border-white/10 text-white/70 bg-white/5">
            Real-time Insights
          </Badge>
          <h2 className="font-display text-5xl md:text-6xl font-extralight text-white mb-6 leading-tight">
            Built for Performance
          </h2>
          <p className="font-text text-xl text-white/60 max-w-2xl mx-auto leading-relaxed">
            Every interaction is optimized. Every insight is instant. Experience the difference that thoughtful
            engineering makes.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-16">
          {metrics.map((metric, index) => (
            <Card key={index} className="bg-white/5 border-white/10 backdrop-blur-xl">
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
                <CardTitle className="font-text text-sm font-medium text-white/70">{metric.label}</CardTitle>
                <metric.icon className="h-4 w-4 text-white/40" />
              </CardHeader>
              <CardContent>
                <div className="font-display text-3xl font-light text-white mb-2">{metric.value}</div>
                <p className="font-text text-xs text-green-400 flex items-center">
                  <TrendingUp className="w-3 h-3 mr-1" />
                  {metric.change} this month
                </p>
              </CardContent>
            </Card>
          ))}
        </div>

        {/* System Overview */}
        <Card className="bg-white/5 border-white/10 backdrop-blur-xl">
          <CardHeader>
            <CardTitle className="font-display text-2xl font-light text-white">System Overview</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-12">
              <div className="space-y-6">
                <h3 className="font-text text-lg font-medium text-white/90">Infrastructure</h3>
                <div className="space-y-4">
                  {["Global Nodes: 47 Active", "Average Latency: 12ms", "Cache Hit Rate: 94.7%"].map((item, i) => (
                    <div key={i} className="flex justify-between font-text text-sm">
                      <span className="text-white/60">{item.split(":")[0]}</span>
                      <span className="text-white font-medium">{item.split(":")[1]}</span>
                    </div>
                  ))}
                </div>
              </div>

              <div className="space-y-6">
                <h3 className="font-text text-lg font-medium text-white/90">Processing</h3>
                <div className="space-y-4">
                  {["Compute Units: 847 Active", "Memory Pool: 2.4TB", "Queue Depth: 0.02ms"].map((item, i) => (
                    <div key={i} className="flex justify-between font-text text-sm">
                      <span className="text-white/60">{item.split(":")[0]}</span>
                      <span className="text-white font-medium">{item.split(":")[1]}</span>
                    </div>
                  ))}
                </div>
              </div>

              <div className="space-y-6">
                <h3 className="font-text text-lg font-medium text-white/90">Storage</h3>
                <div className="space-y-4">
                  {["Total Capacity: 847PB", "Replication: 3x Global", "Consistency: 99.99%"].map((item, i) => (
                    <div key={i} className="flex justify-between font-text text-sm">
                      <span className="text-white/60">{item.split(":")[0]}</span>
                      <span className="text-white font-medium">{item.split(":")[1]}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </section>
  )
}
