import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Download, Github, ExternalLink } from "lucide-react"

export default function TechnicalSpecs() {
  const specifications = [
    {
      category: "Performance",
      specs: [
        { name: "Response Time", value: "< 100ms globally" },
        { name: "Throughput", value: "2.4M requests/sec" },
        { name: "Uptime", value: "99.99% SLA" },
        { name: "Scalability", value: "Auto-scaling" },
      ],
    },
    {
      category: "Infrastructure",
      specs: [
        { name: "Global Presence", value: "47 regions" },
        { name: "Edge Network", value: "Multi-tier CDN" },
        { name: "Load Balancing", value: "Intelligent routing" },
        { name: "Monitoring", value: "Real-time telemetry" },
      ],
    },
    {
      category: "Security",
      specs: [
        { name: "Encryption", value: "End-to-end AES-256" },
        { name: "Authentication", value: "Multi-factor support" },
        { name: "Compliance", value: "SOC 2, GDPR ready" },
        { name: "Audit", value: "Complete activity logs" },
      ],
    },
    {
      category: "Integration",
      specs: [
        { name: "API", value: "RESTful + GraphQL" },
        { name: "Webhooks", value: "Real-time events" },
        { name: "SDKs", value: "All major languages" },
        { name: "Documentation", value: "Interactive guides" },
      ],
    },
  ]

  return (
    <section className="py-32 px-4">
      <div className="max-w-7xl mx-auto">
        <div className="text-center mb-20">
          <Badge variant="outline" className="mb-6 border-white/10 text-white/70 bg-white/5">
            Technical Details
          </Badge>
          <h2 className="font-display text-5xl md:text-6xl font-extralight text-white mb-6 leading-tight">
            Built to Last
          </h2>
          <p className="font-text text-xl text-white/60 max-w-2xl mx-auto leading-relaxed">
            Enterprise-grade infrastructure designed for reliability, security, and scale. Every component is crafted
            with precision and care.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-8 mb-20">
          {specifications.map((category, index) => (
            <Card key={index} className="bg-white/5 border-white/10 backdrop-blur-xl">
              <CardHeader>
                <CardTitle className="font-display text-xl font-light text-white">{category.category}</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-6">
                  {category.specs.map((spec, specIndex) => (
                    <div
                      key={specIndex}
                      className="flex justify-between items-center py-3 border-b border-white/5 last:border-b-0"
                    >
                      <span className="font-text text-white/60">{spec.name}</span>
                      <span className="font-text text-white font-medium">{spec.value}</span>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>

        {/* Performance Highlights */}
        <Card className="bg-white/5 border-white/10 backdrop-blur-xl mb-20">
          <CardHeader>
            <CardTitle className="font-display text-2xl font-light text-white">Performance at Scale</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-12">
              <div className="text-center">
                <div className="font-display text-5xl font-extralight text-white mb-3">2.4PB</div>
                <div className="font-text text-white/60">Data Processed Daily</div>
                <div className="font-text text-xs text-white/40 mt-2">Across all regions</div>
              </div>
              <div className="text-center">
                <div className="font-display text-5xl font-extralight text-white mb-3">{"<"}100ms</div>
                <div className="font-text text-white/60">Global Response Time</div>
                <div className="font-text text-xs text-white/40 mt-2">99th percentile</div>
              </div>
              <div className="text-center">
                <div className="font-display text-5xl font-extralight text-white mb-3">99.99%</div>
                <div className="font-text text-white/60">Uptime Guarantee</div>
                <div className="font-text text-xs text-white/40 mt-2">Enterprise SLA</div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Call to Action */}
        <div className="text-center">
          <div className="flex flex-col sm:flex-row gap-4 justify-center mb-12">
            <Button size="lg" className="bg-white text-black hover:bg-white/90 px-8 py-4 rounded-full font-medium">
              <Download className="mr-2 w-4 h-4" />
              Get Started
            </Button>
            <Button
              size="lg"
              variant="outline"
              className="border-white/20 text-white hover:bg-white/5 px-8 py-4 bg-transparent rounded-full backdrop-blur-sm"
            >
              <Github className="mr-2 w-4 h-4" />
              View Source
            </Button>
            <Button
              size="lg"
              variant="outline"
              className="border-white/20 text-white hover:bg-white/5 px-8 py-4 bg-transparent rounded-full backdrop-blur-sm"
            >
              <ExternalLink className="mr-2 w-4 h-4" />
              Documentation
            </Button>
          </div>

          <div className="flex flex-wrap justify-center gap-8 font-text text-sm text-white/50">
            <span>• Instant deployment</span>
            <span>• Auto-scaling</span>
            <span>• 24/7 support</span>
            <span>• Enterprise ready</span>
          </div>
        </div>
      </div>
    </section>
  )
}
