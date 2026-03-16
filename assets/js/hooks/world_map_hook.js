const TILE_SIZE = 20
const MAP_COLS = 45
const MAP_ROWS = 26
const TOOLTIP_WIDTH = 176
const TOOLTIP_HEIGHT = 88

function hash(x, y) {
  const value = Math.sin(x * 127.1 + y * 311.7) * 43758.5453
  return value - Math.floor(value)
}

function smooth(x, y) {
  const ix = Math.floor(x)
  const iy = Math.floor(y)
  const fx = x - ix
  const fy = y - iy
  const ux = fx * fx * (3 - 2 * fx)
  const uy = fy * fy * (3 - 2 * fy)
  const a = hash(ix, iy)
  const b = hash(ix + 1, iy)
  const c = hash(ix, iy + 1)
  const d = hash(ix + 1, iy + 1)

  return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy
}

function fbm(x, y) {
  let value = 0
  let amplitude = 1
  let frequency = 1
  let maxAmplitude = 0

  for (let index = 0; index < 4; index += 1) {
    value += smooth(x * frequency * 0.07, y * frequency * 0.07) * amplitude
    maxAmplitude += amplitude
    amplitude *= 0.5
    frequency *= 2
  }

  return value / maxAmplitude
}

const COLORS = {
  0: ["#0c1e2e", "#0e2232"],
  1: ["#162e22", "#183224"],
  2: ["#142a18", "#162e1a"],
  3: ["#10240e", "#122810"],
  4: ["#2a2820", "#2e2c22"],
}

function autoPlace(cities) {
  const positions = [
    {col: 10, row: 11},
    {col: 24, row: 6},
    {col: 36, row: 18},
    {col: 15, row: 20},
    {col: 30, row: 12},
    {col: 8, row: 5},
    {col: 38, row: 8},
    {col: 22, row: 20},
  ]

  return cities.map((city, index) => ({
    ...city,
    col: city.col ?? positions[index % positions.length].col,
    row: city.row ?? positions[index % positions.length].row,
  }))
}

function generateTerrain(cities) {
  const map = []

  for (let row = 0; row < MAP_ROWS; row += 1) {
    map[row] = []

    for (let col = 0; col < MAP_COLS; col += 1) {
      const noise = fbm(col + 10, row + 5)

      if (noise < 0.32) {
        map[row][col] = 0
      } else if (noise < 0.38) {
        map[row][col] = 1
      } else if (noise < 0.58) {
        map[row][col] = 2
      } else if (noise < 0.72) {
        map[row][col] = 3
      } else {
        map[row][col] = 4
      }
    }
  }

  cities.forEach(city => {
    for (let rowOffset = -2; rowOffset <= 2; rowOffset += 1) {
      for (let colOffset = -2; colOffset <= 2; colOffset += 1) {
        const row = city.row + rowOffset
        const col = city.col + colOffset

        if (
          row >= 0 &&
            row < MAP_ROWS &&
            col >= 0 &&
            col < MAP_COLS &&
            Math.abs(rowOffset) + Math.abs(colOffset) < 4
        ) {
          map[row][col] = 2
        }
      }
    }
  })

  return map
}

function generateRoads(cities) {
  const roads = new Set()

  function drawRoad(from, to) {
    let x = from.col
    let y = from.row

    while (x !== to.col || y !== to.row) {
      roads.add(`${x},${y}`)

      if (Math.abs(to.col - x) > Math.abs(to.row - y)) {
        x += to.col > x ? 1 : -1
      } else {
        y += to.row > y ? 1 : -1
      }
    }
  }

  for (let index = 0; index < cities.length; index += 1) {
    const nextIndex = (index + 1) % cities.length
    drawRoad(cities[index], cities[nextIndex])
  }

  return roads
}

function generateFog(cities, roads) {
  const fog = []

  for (let row = 0; row < MAP_ROWS; row += 1) {
    fog[row] = []

    for (let col = 0; col < MAP_COLS; col += 1) {
      fog[row][col] = 1
    }
  }

  cities.forEach(city => {
    const radius = 8

    for (let rowOffset = -radius; rowOffset <= radius; rowOffset += 1) {
      for (let colOffset = -radius; colOffset <= radius; colOffset += 1) {
        const row = city.row + rowOffset
        const col = city.col + colOffset

        if (row >= 0 && row < MAP_ROWS && col >= 0 && col < MAP_COLS) {
          const distance = Math.sqrt(rowOffset * rowOffset + colOffset * colOffset)

          if (distance < radius) {
            fog[row][col] = Math.min(fog[row][col], distance / radius)
          }
        }
      }
    }
  })

  roads.forEach(key => {
    const [col, row] = key.split(",").map(Number)

    for (let rowOffset = -3; rowOffset <= 3; rowOffset += 1) {
      for (let colOffset = -3; colOffset <= 3; colOffset += 1) {
        const fogRow = row + rowOffset
        const fogCol = col + colOffset

        if (fogRow >= 0 && fogRow < MAP_ROWS && fogCol >= 0 && fogCol < MAP_COLS) {
          const distance = Math.sqrt(rowOffset * rowOffset + colOffset * colOffset)

          if (distance < 3) {
            fog[fogRow][fogCol] = Math.min(fog[fogRow][fogCol], 0.3 + distance * 0.15)
          }
        }
      }
    }
  })

  return fog
}

function createPackets(roads, cities) {
  const roadSegments = [...roads].map(key => {
    const [x, y] = key.split(",").map(Number)
    return {x, y}
  })

  if (roadSegments.length === 0) {
    return {roadSegments, packets: []}
  }

  const packetCount = Math.min(8, Math.max(3, cities.length * 2))
  const packets = []

  for (let index = 0; index < packetCount; index += 1) {
    const roadIndex = Math.floor(Math.random() * roadSegments.length)

    packets.push({
      idx: roadIndex,
      progress: 0,
      speed: 0.02 + Math.random() * 0.03,
      color: cities[index % cities.length]?.color || "#3ddc84",
    })
  }

  return {roadSegments, packets}
}

function drawTerrain(ctx, terrain, roads) {
  for (let row = 0; row < MAP_ROWS; row += 1) {
    for (let col = 0; col < MAP_COLS; col += 1) {
      const tile = terrain[row][col]
      const variant = (col * 7 + row * 13) % 2
      ctx.fillStyle = COLORS[tile][variant]
      ctx.fillRect(col * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE)

      if (tile === 3 && hash(col, row) > 0.45) {
        ctx.fillStyle = "#1a3a18"
        ctx.fillRect(col * TILE_SIZE + 8, row * TILE_SIZE + 4, 3, 6)
        ctx.fillStyle = "#1e4420"
        ctx.fillRect(col * TILE_SIZE + 5, row * TILE_SIZE + 2, 9, 5)
      }

      if (tile === 4 && hash(col + 1, row + 1) > 0.4) {
        ctx.fillStyle = "#3a3830"
        ctx.fillRect(col * TILE_SIZE + 4, row * TILE_SIZE + 6, 8, 4)
        ctx.fillRect(col * TILE_SIZE + 6, row * TILE_SIZE + 3, 4, 3)
      }

      if (roads.has(`${col},${row}`)) {
        ctx.fillStyle = "rgba(61,220,132,0.12)"
        ctx.fillRect(col * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE)

        if ((col + row) % 3 === 0) {
          ctx.fillStyle = "rgba(61,220,132,0.2)"
          ctx.fillRect(col * TILE_SIZE + 8, row * TILE_SIZE + 8, 3, 3)
        }
      }
    }
  }
}

function drawFog(ctx, fog) {
  for (let row = 0; row < MAP_ROWS; row += 1) {
    for (let col = 0; col < MAP_COLS; col += 1) {
      if (fog[row][col] > 0.05) {
        ctx.fillStyle = `rgba(4,8,4,${fog[row][col] * 0.88})`
        ctx.fillRect(col * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE)
      }
    }
  }
}

function drawCity(ctx, city, tick) {
  const x = city.col * TILE_SIZE
  const y = city.row * TILE_SIZE
  const centerX = x + TILE_SIZE / 2
  const centerY = y + TILE_SIZE / 2
  const buildingCount = Math.max(2, Math.min(5, city.depts || 2))
  const islandRows = [
    {offsetY: -2, start: -1, end: 2},
    {offsetY: -1, start: -2, end: 3},
    {offsetY: 0, start: -3, end: 4},
    {offsetY: 1, start: -3, end: 4},
    {offsetY: 2, start: -2, end: 3},
    {offsetY: 3, start: -1, end: 2},
  ]
  const innerRows = [
    {offsetY: -1, start: -1, end: 2},
    {offsetY: 0, start: -2, end: 3},
    {offsetY: 1, start: -2, end: 3},
    {offsetY: 2, start: -1, end: 2},
  ]
  const buildingSlots = [
    {offsetX: -26, width: 10, height: 14},
    {offsetX: -10, width: 12, height: 19},
    {offsetX: 8, width: 10, height: 15},
    {offsetX: 22, width: 8, height: 11},
    {offsetX: 34, width: 7, height: 9},
  ]

  ctx.fillStyle = city.color
  ctx.globalAlpha = 0.05 + Math.sin(tick * 0.04) * 0.02
  ctx.fillRect(x - 42, y - 24, TILE_SIZE + 84, TILE_SIZE + 58)
  ctx.globalAlpha = 1

  islandRows.forEach(row => {
    ctx.fillStyle = "#49422f"
    ctx.fillRect(
      centerX + row.start * 8,
      centerY + row.offsetY * 8,
      (row.end - row.start) * 8,
      8
    )
  })

  innerRows.forEach(row => {
    ctx.fillStyle = "#182e1c"
    ctx.fillRect(
      centerX + row.start * 8,
      centerY + row.offsetY * 8,
      (row.end - row.start) * 8,
      8
    )
  })

  ctx.fillStyle = "rgba(61,220,132,0.18)"
  ctx.fillRect(centerX - 16, centerY + 12, 32, 4)
  ctx.fillRect(centerX - 10, centerY + 8, 20, 4)

  for (let index = 0; index < buildingCount; index += 1) {
    const slot = buildingSlots[index]
    const buildingX = centerX + slot.offsetX
    const buildingY = centerY + 8
    const litBase = Math.sin(tick * 0.05 + city.col + index) > -0.15

    ctx.fillStyle = "#0a1610"
    ctx.fillRect(buildingX, buildingY - slot.height, slot.width, slot.height)
    ctx.strokeStyle = city.color
    ctx.lineWidth = 1
    ctx.strokeRect(buildingX, buildingY - slot.height, slot.width, slot.height)

    for (let windowY = buildingY - slot.height + 4; windowY < buildingY - 2; windowY += 5) {
      for (let windowX = buildingX + 2; windowX < buildingX + slot.width - 2; windowX += 4) {
        const lit = Math.sin(tick * 0.08 + windowX * 0.2 + windowY * 0.15) > (litBase ? -0.4 : 0.2)
        ctx.fillStyle = lit ? city.color : "#0a1610"
        ctx.globalAlpha = lit ? 0.55 : 1
        ctx.fillRect(windowX, windowY, 2, 2)
      }
    }

    ctx.globalAlpha = 1
  }

  if (Math.sin(tick * 0.1 + city.row) > 0.25) {
    ctx.fillStyle = city.status === "degraded" ? "#ff9b54" : city.color
    ctx.fillRect(centerX - 1, centerY - 20, 2, 2)
  }

  if (city.status === "offline") {
    ctx.fillStyle = "#ff4444"
    ctx.globalAlpha = 0.28
    ctx.fillRect(centerX - 26, centerY - 14, 52, 30)
    ctx.globalAlpha = 1
  }

  ctx.font = "9px IBM Plex Mono, monospace"
  ctx.textAlign = "center"
  ctx.fillStyle = city.color
  ctx.fillText(city.name.toUpperCase(), centerX, y + TILE_SIZE + 28)
  ctx.fillStyle = "#7aa18a"
  ctx.font = "8px IBM Plex Mono, monospace"
  ctx.fillText(city.region, centerX, y + TILE_SIZE + 39)
  ctx.textAlign = "left"
}

function drawPackets(ctx, roadSegments, packets) {
  packets.forEach(packet => {
    packet.progress += packet.speed

    if (packet.progress >= 1) {
      packet.progress = 0
      packet.idx = (packet.idx + 1) % roadSegments.length
    }

    const current = roadSegments[packet.idx]
    const next = roadSegments[(packet.idx + 1) % roadSegments.length]
    const x = (current.x + (next.x - current.x) * packet.progress) * TILE_SIZE + TILE_SIZE / 2
    const y = (current.y + (next.y - current.y) * packet.progress) * TILE_SIZE + TILE_SIZE / 2

    ctx.fillStyle = packet.color
    ctx.globalAlpha = 0.6
    ctx.fillRect(x - 2, y - 2, 3, 3)
    ctx.globalAlpha = 1
  })
}

function getHoveredCity(cities, mapX, mapY) {
  const mapCol = Math.floor(mapX / TILE_SIZE)
  const mapRow = Math.floor(mapY / TILE_SIZE)

  return cities.find(city => {
    const colDistance = mapCol - city.col
    const rowDistance = mapRow - city.row

    return (colDistance * colDistance) / 16 + (rowDistance * rowDistance) / 9 <= 1.65
  })
}

function parseCities(data) {
  try {
    const cities = JSON.parse(data || "[]")
    return Array.isArray(cities) ? cities : []
  } catch (_error) {
    return []
  }
}

function parseLabels(data) {
  try {
    const labels = JSON.parse(data || "{}")
    return labels && typeof labels === "object" ? labels : {}
  } catch (_error) {
    return {}
  }
}

function resetTooltip(tooltip) {
  tooltip.replaceChildren()
}

function appendTooltipLine(tooltip, text, color = null) {
  const line = document.createElement("div")

  if (color) {
    line.style.color = color
  }

  line.textContent = text
  tooltip.append(line)
}

function renderCityTooltip(tooltip, city, labels) {
  const statusLabels = labels.statuses || {}
  const statusText = statusLabels[city.status] || city.status
  const statusColor =
    city.status === "online" ? "#3ddc84" : city.status === "offline" ? "#ff4444" : "#ff9b54"

  resetTooltip(tooltip)
  appendTooltipLine(tooltip, city.name, city.color)
  appendTooltipLine(tooltip, city.region, "#7aa18a")
  appendTooltipLine(
    tooltip,
    `${city.depts} ${labels.departments || ""} · ${city.agents} ${labels.agents || ""}`.trim()
  )
  appendTooltipLine(tooltip, statusText, statusColor)
}

function pointerPosition(event, root, canvas, worldWidth, worldHeight) {
  const rootRect = root.getBoundingClientRect()
  const rect = canvas.getBoundingClientRect()
  const cssX = event.clientX - rootRect.left
  const cssY = event.clientY - rootRect.top
  const scaleX = worldWidth / rect.width
  const scaleY = worldHeight / rect.height
  const mapX = (event.clientX - rect.left) * scaleX
  const mapY = (event.clientY - rect.top) * scaleY

  return {
    cssX,
    cssY,
    mapX,
    mapY,
    rootRect,
  }
}

function setupWorldMap(hook) {
  const root = hook.el
  const canvas = root.querySelector("canvas")
  const tooltip = root.querySelector("[id$='-tooltip']")

  if (!canvas || !tooltip) {
    return () => {}
  }

  const ctx = canvas.getContext("2d")
  const worldWidth = MAP_COLS * TILE_SIZE
  const worldHeight = MAP_ROWS * TILE_SIZE

  canvas.width = worldWidth
  canvas.height = worldHeight

  const cities = autoPlace(parseCities(root.dataset.cities))
  const labels = parseLabels(root.dataset.labels)
  const terrain = generateTerrain(cities)
  const roads = generateRoads(cities)
  const fog = generateFog(cities, roads)
  const {roadSegments, packets} = createPackets(roads, cities)

  let tick = 0
  let frameId = null

  const render = () => {
    ctx.clearRect(0, 0, worldWidth, worldHeight)
    drawTerrain(ctx, terrain, roads)
    drawFog(ctx, fog)
    drawPackets(ctx, roadSegments, packets)
    cities.forEach(city => drawCity(ctx, city, tick))
    tick += 1
    frameId = window.requestAnimationFrame(render)
  }

  const showTooltip = event => {
    const {cssX, cssY, mapX, mapY, rootRect} = pointerPosition(
      event,
      root,
      canvas,
      worldWidth,
      worldHeight
    )
    const city = getHoveredCity(cities, mapX, mapY)

    if (!city) {
      tooltip.hidden = true
      root.style.cursor = "default"
      return
    }

    tooltip.hidden = false
    tooltip.style.left = `${Math.max(0, Math.min(cssX + 14, rootRect.width - TOOLTIP_WIDTH))}px`
    tooltip.style.top = `${Math.max(0, Math.min(cssY + 14, rootRect.height - TOOLTIP_HEIGHT))}px`
    renderCityTooltip(tooltip, city, labels)
    root.style.cursor = "pointer"
  }

  const hideTooltip = () => {
    tooltip.hidden = true
    root.style.cursor = "default"
  }

  const handleClick = event => {
    const {mapX, mapY} = pointerPosition(event, root, canvas, worldWidth, worldHeight)
    const city = getHoveredCity(cities, mapX, mapY)

    if (city) {
      hook.pushEvent("navigate_city", {city_id: city.id})
    }
  }

  canvas.addEventListener("mousemove", showTooltip)
  canvas.addEventListener("mouseleave", hideTooltip)
  canvas.addEventListener("click", handleClick)

  render()

  return () => {
    if (frameId) {
      window.cancelAnimationFrame(frameId)
    }

    canvas.removeEventListener("mousemove", showTooltip)
    canvas.removeEventListener("mouseleave", hideTooltip)
    canvas.removeEventListener("click", handleClick)
    tooltip.hidden = true
    root.style.cursor = "default"
  }
}

export const WorldMapHook = {
  mounted() {
    this._cleanup = setupWorldMap(this)
  },

  updated() {
    if (this._cleanup) {
      this._cleanup()
    }

    this._cleanup = setupWorldMap(this)
  },

  destroyed() {
    if (this._cleanup) {
      this._cleanup()
    }
  },
}
