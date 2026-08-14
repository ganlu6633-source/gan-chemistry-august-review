import { describe, expect, it } from 'vitest'
import { ABILITY_MAP_BLUEPRINTS, validateAbilityMapBlueprint } from './abilityMap'
import type { GradeBand } from '../domain/types'

const GRADES = Object.keys(ABILITY_MAP_BLUEPRINTS) as GradeBand[]

describe('ability map blueprints', () => {
  it.each(GRADES)('%s has unique nodes and no dangling relation endpoints', (gradeBand) => {
    const blueprint = ABILITY_MAP_BLUEPRINTS[gradeBand]
    const ids = blueprint.stages.flatMap((stage) => stage.skillIds)
    const result = validateAbilityMapBlueprint(gradeBand, ids)

    expect(new Set(ids).size).toBe(ids.length)
    expect(result.duplicateIds).toEqual([])
    expect(result.danglingRelations).toEqual([])
  })

  it.each(GRADES)('%s main learning route is acyclic', (gradeBand) => {
    const blueprint = ABILITY_MAP_BLUEPRINTS[gradeBand]
    const ids = blueprint.stages.flatMap((stage) => stage.skillIds)
    const outgoing = new Map(ids.map((id) => [id, blueprint.relations.filter((edge) => edge.kind === 'main' && edge.from === id).map((edge) => edge.to)]))
    const visiting = new Set<string>()
    const visited = new Set<string>()
    const hasCycle = (id: string): boolean => {
      if (visiting.has(id)) return true
      if (visited.has(id)) return false
      visiting.add(id)
      if ((outgoing.get(id) ?? []).some(hasCycle)) return true
      visiting.delete(id)
      visited.add(id)
      return false
    }

    expect(ids.some(hasCycle)).toBe(false)
  })

  it.each(GRADES)('%s is one connected knowledge map when main and support relations are combined', (gradeBand) => {
    const blueprint = ABILITY_MAP_BLUEPRINTS[gradeBand]
    const ids = blueprint.stages.flatMap((stage) => stage.skillIds)
    const neighbors = new Map(ids.map((id) => [id, new Set<string>()]))
    for (const edge of blueprint.relations) {
      neighbors.get(edge.from)?.add(edge.to)
      neighbors.get(edge.to)?.add(edge.from)
    }
    const reached = new Set<string>()
    const queue = ids.length ? [ids[0]] : []
    while (queue.length) {
      const id = queue.shift()!
      if (reached.has(id)) continue
      reached.add(id)
      for (const next of neighbors.get(id) ?? []) if (!reached.has(next)) queue.push(next)
    }

    expect(reached.size).toBe(ids.length)
  })
})
