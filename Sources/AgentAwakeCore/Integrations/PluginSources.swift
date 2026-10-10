import Foundation

/// Plugin files for agents whose extension point is code running inside the agent (OpenCode, Kilo, Amp, omp, pi).
/// Each one reports our action names (start, beat, needsYou, stop, failed, end) by spawning
/// `agentawake hook <agent> <action>` detached with `{session_id, cwd, prompt?, parent_session_id?, message?,
/// status?}` on stdin. It never awaits the child, catches every error, and skips subagent turns (their activity
/// only keeps the parent session alive).
enum PluginSources {
    static func header(_ name: String, _ agent: String) -> String {
        """
        // Agent Awake plugin for \(name): tells the Agent Awake menu bar app when work starts, needs you and finishes
        // (runs `agentawake hook \(agent) <action>`). Written by Agent Awake; Disconnect in Agent Awake deletes this file.
        """
    }

    /// The detached, fire-and-forget spawn shared by every plugin. `typed` adds TypeScript annotations.
    static func sender(bin: String, agent: String, typed: Bool) -> String {
        let sig = typed ? "action: string, payload: Record<string, unknown>): void" : "action, payload)"
        return """
        import { spawn } from "node:child_process"
        import { existsSync } from "node:fs"

        const BIN = \(JSONValue.quote(bin))
        const AGENT = \(JSONValue.quote(agent))
        const BEAT_EVERY_MS = 20000

        function send(\(sig) {
          try {
            if (!existsSync(BIN)) return
            const child = spawn(BIN, ["hook", AGENT, action], { stdio: ["pipe", "ignore", "ignore"], detached: true })
            child.on("error", () => {})
            child.stdin.on("error", () => {})
            child.stdin.end(JSON.stringify(payload))
            child.unref()
          } catch {}
        }
        """
    }

    /// OpenCode (v1 `server()` and v2 `setup()` from one default export) and Kilo (v1 API).
    static func opencode(name: String, agent: String, bin: String) -> String {
        header(name, agent) + "\n" + sender(bin: bin, agent: agent, typed: false) + "\n\n" + #"""
        const clip = (text, n = 300) => (typeof text === "string" && text ? text.slice(0, n) : undefined)

        function permissionText(p) {
          if (typeof p.title === "string" && p.title) return clip(p.title)
          const patterns = Array.isArray(p.patterns) && p.patterns.length ? ": " + p.patterns.join(", ") : ""
          return clip(typeof p.permission === "string" ? `Allow ${p.permission}${patterns}` : "Permission needed")
        }

        function questionText(p) {
          const q = Array.isArray(p.questions) ? p.questions[0] : undefined
          return clip(q?.question ?? q?.header ?? p.question) ?? "Question"
        }

        function promptText(parts) {
          if (!Array.isArray(parts)) return undefined
          return clip(parts.filter((part) => part?.type === "text" && !part.synthetic).map((part) => part.text).join("\n"), 500)
        }

        // Turns OpenCode bus events into our actions. Events run one at a time so a parent lookup can't reorder them.
        function tracker(baseDir, lookupParent) {
          const busy = new Set()
          const lastBeat = new Map()
          const parents = new Map()
          const dirs = new Map()
          const prompts = new Map()
          let queue = Promise.resolve()

          const remember = (info) => {
            if (!info || typeof info.id !== "string") return
            parents.set(info.id, typeof info.parentID === "string" ? info.parentID : null)
            if (typeof info.directory === "string") dirs.set(info.id, info.directory)
          }
          const parentOf = async (id) => {
            if (parents.has(id)) return parents.get(id)
            let parent = null
            try {
              const found = await lookupParent(id)
              parent = typeof found === "string" ? found : null
            } catch {}
            parents.set(id, parent)
            return parent
          }
          const base = (id) => ({ session_id: id, cwd: dirs.get(id) ?? baseDir })
          const beat = (id, parent) => {
            const now = Date.now()
            if (now - (lastBeat.get(id) ?? 0) < BEAT_EVERY_MS) return
            lastBeat.set(id, now)
            send("beat", parent ? { ...base(id), parent_session_id: parent } : base(id))
          }
          const finish = (id, extra) => {
            if (!busy.has(id)) return
            busy.delete(id)
            send("stop", { ...base(id), ...extra })
          }

          async function handle(type, p) {
            if (type === "session.created" || type === "session.updated") return remember(p.info)
            const id = p.sessionID ?? p.part?.sessionID ?? p.info?.sessionID ?? p.info?.id
            if (typeof id !== "string") return
            const parent = await parentOf(id)
            if (parent) {
              // A subagent session: a question or permission still needs the user (reported on the parent);
              // anything else just keeps the parent alive.
              if (type === "permission.asked" || type === "permission.updated") send("needsYou", { ...base(parent), message: permissionText(p) })
              else if (type === "question.asked") send("needsYou", { ...base(parent), message: questionText(p) })
              else if (type === "session.status" || type === "message.part.updated" || type.endsWith(".replied")) beat(id, parent)
              return
            }
            switch (type) {
              case "session.status": {
                const status = p.status?.type
                if (status === "busy" || status === "retry") {
                  if (busy.has(id)) return beat(id)
                  busy.add(id)
                  lastBeat.set(id, Date.now())
                  const prompt = prompts.get(id)
                  prompts.delete(id)
                  send("start", prompt ? { ...base(id), prompt } : base(id))
                } else if (status === "idle") finish(id)
                return
              }
              case "session.idle":
                return finish(id)
              case "session.error": {
                const error = p.error ?? {}
                if (error.name === "MessageAbortedError") return finish(id, { status: "aborted" })
                if (!busy.has(id)) return
                busy.delete(id)
                send("failed", { ...base(id), message: clip(String(error.data?.message ?? error.message ?? error.name ?? "Error")) })
                return
              }
              case "permission.asked":
              case "permission.updated":
                return send("needsYou", { ...base(id), message: permissionText(p) })
              case "question.asked":
                return send("needsYou", { ...base(id), message: questionText(p) })
              case "permission.replied":
              case "question.replied":
              case "question.rejected":
                lastBeat.delete(id)
                return beat(id)
              case "message.part.updated":
                if (busy.has(id)) beat(id)
                return
              case "session.deleted":
                busy.delete(id)
                send("end", base(id))
                parents.delete(id)
                dirs.delete(id)
                return
            }
          }

          return {
            event(type, properties) {
              if (typeof type !== "string") return
              queue = queue.then(() => handle(type, properties ?? {})).catch(() => {})
            },
            prompt(id, text) {
              if (typeof id === "string" && text) prompts.set(id, text)
            },
          }
        }

        export default {
          id: "agentawake",
          // OpenCode 2
          setup(ctx) {
            const controller = new AbortController()
            try {
              const t = tracker(ctx?.location?.directory ?? process.cwd(), async (id) => {
                const found = await ctx.session.get({ sessionID: id })
                return (found?.data ?? found)?.parentID
              })
              void (async () => {
                try {
                  for await (const ev of ctx.event.subscribe({ signal: controller.signal })) {
                    try {
                      t.event(ev?.type, ev?.data ?? ev?.properties)
                    } catch {}
                  }
                } catch {}
              })()
            } catch {}
            return () => controller.abort()
          },
          // OpenCode 1.18.29+ and Kilo
          async server(input) {
            const t = tracker(input?.directory ?? process.cwd(), async (id) => {
              const found = await input.client.session.get({ path: { id } })
              return (found?.data ?? found)?.parentID
            })
            return {
              event: async ({ event }) => {
                try {
                  t.event(event?.type, event?.properties)
                } catch {}
              },
              "chat.message": async (info, output) => {
                try {
                  t.prompt(info?.sessionID, promptText(output?.parts))
                } catch {}
              },
            }
          },
        }

        """#
    }

    /// Amp plugin API (Neo CLI): request events are awaited, so handlers queue work and return at once.
    static func amp(bin: String) -> String {
        header("Amp", "amp") + "\n" + sender(bin: bin, agent: "amp", typed: true) + "\n\n" + #"""
        const clip = (text: unknown, n = 500) => (typeof text === "string" && text ? text.slice(0, n) : undefined)

        export default function (amp: any) {
          try {
            if (amp?.system?.executor?.kind === "remote") return
          } catch {}
          const parents = new Map<string, string | null>()
          const watched = new Map<string, { unsubscribe(): void }>()
          const started = new Set<string>()
          const lastBeat = new Map<string, number>()
          let queue: Promise<unknown> = Promise.resolve()

          const run = (fn: () => unknown) => {
            queue = queue.then(fn).catch(() => {})
          }
          const cwd = () => {
            try {
              return process.cwd()
            } catch {
              return undefined
            }
          }
          const base = (id: string) => ({ session_id: id, cwd: cwd() })
          // Child threads (subagents) only keep their parent alive. parentThreadID() works for the handler's own thread.
          const parentOf = async (id: string, ctx: any): Promise<string | null> => {
            if (parents.has(id)) return parents.get(id) ?? null
            let parent: string | null = null
            try {
              if (ctx?.thread?.id === id) parent = (await ctx.thread.parentThreadID()) ?? null
            } catch {}
            parents.set(id, parent)
            return parent
          }
          const beat = (id: string, parent: string | null) => {
            const now = Date.now()
            if (now - (lastBeat.get(id) ?? 0) < BEAT_EVERY_MS) return
            lastBeat.set(id, now)
            send("beat", parent ? { ...base(id), parent_session_id: parent } : base(id))
          }
          const on = (event: string, handler: (event: any, ctx: any) => void, result?: unknown) => {
            try {
              amp.on(event, (event: any, ctx: any) => {
                try {
                  handler(event, ctx)
                } catch {}
                return result
              })
            } catch {}
          }

          on("session.start", (event, ctx) => {
            const id = event?.thread?.id
            if (typeof id !== "string" || watched.has(id)) return
            let last: string | undefined
            const subscription = ctx?.thread?.state?.subscribe?.((state: string) => {
              const previous = last
              if (state === previous) return
              last = state
              run(async () => {
                const parent = await parentOf(id, ctx)
                if (state === "awaiting-approval") send("needsYou", { ...base(parent ?? id), message: "Waiting for tool approval" })
                else if (state === "running" && previous === "awaiting-approval") {
                  lastBeat.delete(id)
                  beat(id, parent)
                }
              })
            })
            if (subscription) watched.set(id, subscription)
          })

          on("agent.start", (event, ctx) => {
            const id = event?.thread?.id
            if (typeof id !== "string") return
            const prompt = clip(event?.message)
            run(async () => {
              const parent = await parentOf(id, ctx)
              if (parent) return beat(id, parent)
              started.add(id)
              lastBeat.set(id, Date.now())
              send("start", { ...base(id), prompt })
            })
          }, {})

          on("tool.result", (event, ctx) => {
            const id = event?.thread?.id
            if (typeof id !== "string") return
            run(async () => beat(id, await parentOf(id, ctx)))
          })

          on("agent.end", (event, ctx) => {
            const id = event?.thread?.id
            if (typeof id !== "string") return
            const status = event?.status
            run(async () => {
              const parent = await parentOf(id, ctx)
              if (parent) return beat(id, parent)
              if (status === "error") send("failed", { ...base(id), message: "The turn ended with an error" })
              else if (status === "cancelled") send("stop", { ...base(id), status: "cancelled" })
              else send("stop", base(id))
            })
          })

          try {
            amp.onDispose(() => {
              try {
                for (const subscription of watched.values()) {
                  try {
                    subscription.unsubscribe()
                  } catch {}
                }
                watched.clear()
                for (const id of started) send("end", base(id))
                started.clear()
              } catch {}
            })
          } catch {}
        }

        """#
    }

    /// oh-my-pi extension. `ctx.agent.kind === "sub"` marks subagents and advisors; `session_stop` is main-only.
    static func omp(bin: String) -> String {
        header("oh-my-pi", "omp") + "\n" + sender(bin: bin, agent: "omp", typed: true) + "\n\n" + #"""
        const clip = (text: unknown, n = 500) => (typeof text === "string" && text ? text.slice(0, n) : undefined)

        export default function (pi: any) {
          const prompts = new Map<string, string>()
          const lastBeat = new Map<string, number>()
          const settled = new Set<string>()

          const sessionOf = (ctx: any): string | undefined => {
            try {
              if (ctx?.agent?.kind === "sub") return undefined
              const id = ctx?.sessionManager?.getSessionId?.()
              return typeof id === "string" && id ? id : undefined
            } catch {
              return undefined
            }
          }
          const base = (id: string, ctx: any) => ({ session_id: id, cwd: typeof ctx?.cwd === "string" ? ctx.cwd : undefined })
          const beat = (id: string, ctx: any, force = false) => {
            const now = Date.now()
            if (!force && now - (lastBeat.get(id) ?? 0) < BEAT_EVERY_MS) return
            lastBeat.set(id, now)
            send("beat", base(id, ctx))
          }
          const on = (event: string, handler: (event: any, ctx: any, id: string) => void) => {
            try {
              pi.on(event, (event: any, ctx: any) => {
                try {
                  const id = sessionOf(ctx)
                  if (id) handler(event, ctx, id)
                } catch {}
                return undefined
              })
            } catch {}
          }

          on("before_agent_start", (event, _ctx, id) => {
            const prompt = clip(event?.prompt)
            if (prompt) prompts.set(id, prompt)
          })
          on("agent_start", (_event, ctx, id) => {
            settled.delete(id)
            lastBeat.set(id, Date.now())
            const prompt = prompts.get(id)
            prompts.delete(id)
            send("start", { ...base(id, ctx), prompt })
          })
          on("tool_result", (_event, ctx, id) => beat(id, ctx))
          on("tool_call", (event, ctx, id) => {
            if (event?.toolName !== "ask") return
            const questions = event?.input?.questions
            send("needsYou", { ...base(id, ctx), message: clip(Array.isArray(questions) ? questions[0]?.question : undefined) ?? "Question" })
          })
          on("tool_approval_requested", (event, ctx, id) => {
            const tool = typeof event?.toolName === "string" ? event.toolName : "a tool"
            send("needsYou", { ...base(id, ctx), message: clip(event?.reason ? `Approve ${tool}: ${event.reason}` : `Approve ${tool}`) })
          })
          on("tool_approval_resolved", (_event, ctx, id) => beat(id, ctx, true))
          on("agent_end", (event, ctx, id) => {
            if (event?.willContinue) return
            const messages = Array.isArray(event?.messages) ? event.messages : []
            const last = [...messages].reverse().find((m: any) => m?.role === "assistant")
            if (last?.stopReason === "error") {
              settled.add(id)
              send("failed", { ...base(id, ctx), message: clip(last.errorMessage) ?? "The turn ended with an error" })
            } else if (last?.stopReason === "aborted") {
              settled.add(id)
              send("stop", { ...base(id, ctx), status: "aborted" })
            }
          })
          on("session_stop", (_event, ctx, id) => {
            if (settled.has(id)) return
            settled.add(id)
            send("stop", base(id, ctx))
          })
          on("session_shutdown", (_event, ctx, id) => send("end", base(id, ctx)))
        }

        """#
    }

    /// pi (earendil-works) extension. `agent_settled` (pi 0.80.4+) is the final "won't continue" signal.
    static func pi(bin: String) -> String {
        header("pi", "pi") + "\n" + sender(bin: bin, agent: "pi", typed: true) + "\n\n" + #"""
        const clip = (text: unknown, n = 500) => (typeof text === "string" && text ? text.slice(0, n) : undefined)

        export default function (pi: any) {
          const prompts = new Map<string, string>()
          const outcomes = new Map<string, string>()
          const lastBeat = new Map<string, number>()

          const sessionOf = (ctx: any): string | undefined => {
            try {
              if (ctx?.agent?.kind === "sub") return undefined
              const id = ctx?.sessionManager?.getSessionId?.()
              return typeof id === "string" && id ? id : undefined
            } catch {
              return undefined
            }
          }
          const base = (id: string, ctx: any) => ({ session_id: id, cwd: typeof ctx?.cwd === "string" ? ctx.cwd : undefined })
          const beat = (id: string, ctx: any, force = false) => {
            const now = Date.now()
            if (!force && now - (lastBeat.get(id) ?? 0) < BEAT_EVERY_MS) return
            lastBeat.set(id, now)
            send("beat", base(id, ctx))
          }
          const on = (event: string, handler: (event: any, ctx: any, id: string) => void) => {
            try {
              pi.on(event, (event: any, ctx: any) => {
                try {
                  const id = sessionOf(ctx)
                  if (id) handler(event, ctx, id)
                } catch {}
                return undefined
              })
            } catch {}
          }

          on("before_agent_start", (event, _ctx, id) => {
            const prompt = clip(event?.prompt)
            if (prompt) prompts.set(id, prompt)
          })
          on("agent_start", (_event, ctx, id) => {
            outcomes.delete(id)
            lastBeat.set(id, Date.now())
            const prompt = prompts.get(id)
            prompts.delete(id)
            send("start", { ...base(id, ctx), prompt })
          })
          on("tool_result", (_event, ctx, id) => beat(id, ctx))
          on("ui_prompt_start", (event, ctx, id) => send("needsYou", { ...base(id, ctx), message: clip(event?.title) ?? "Waiting for your answer" }))
          on("ui_prompt_end", (_event, ctx, id) => beat(id, ctx, true))
          on("agent_before_settle", (event, _ctx, id) => {
            if (typeof event?.outcome === "string") outcomes.set(id, event.outcome)
          })
          on("agent_settled", (event, ctx, id) => {
            const outcome = outcomes.get(id)
            outcomes.delete(id)
            if (event?.aborted || outcome === "aborted") send("stop", { ...base(id, ctx), status: "aborted" })
            else if (outcome === "error") send("failed", { ...base(id, ctx), message: "The run ended with an error" })
            else send("stop", base(id, ctx))
          })
          on("session_shutdown", (event, ctx, id) => {
            if (event?.reason !== "reload") send("end", base(id, ctx))
          })
        }

        """#
    }
}
