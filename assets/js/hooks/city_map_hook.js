const TILE_SIZE = 20
const MAP_COLS = 45
const MAP_ROWS = 26
const TOOLTIP_WIDTH = 180
const TOOLTIP_HEIGHT = 80

const TERRAIN_COLORS = {
  0: ["#0e1e12", "#101f14"],
  1: ["#142a18", "#162e1a"],
  2: ["#182e1c", "#1a321e"],
  3: ["#1a2a1e", "#1c2e20"],
}

const DEFAULT_POSITIONS = [
  {col: 12, row: 10},
  {col: 32, row: 8},
  {col: 22, row: 19},
  {col: 10, row: 18},
  {col: 34, row: 17},
  {col: 18, row: 6},
]

function hash(x, y) {
  const n = Math.sin(x * 127.1 + y * 311.7) * 43758.5453
  return n - Math.floor(n)
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
  let normalizer = 0

  for (let index = 0; index < 4; index += 1) {
    value += smooth(x * frequency * 0.08, y * frequency * 0.08) * amplitude
    normalizer += amplitude
    amplitude *= 0.5
    frequency *= 2
  }

  return value / normalizer
}

function autoPlaceDepartments(departments) {
  return departments.map((department, index) => ({
    ...department,
    col: department.col ?? DEFAULT_POSITIONS[index % DEFAULT_POSITIONS.length].col,
    row: department.row ?? DEFAULT_POSITIONS[index % DEFAULT_POSITIONS.length].row,
  }))
}

function generateTerrain(departments) {
  const terrain = []

  for (let row = 0; row < MAP_ROWS; row += 1) {
    terrain[row] = []

    for (let col = 0; col < MAP_COLS; col += 1) {
      const noise = fbm(col + 30, row + 20)

      if (noise < 0.4) terrain[row][col] = 0
      else if (noise < 0.6) terrain[row][col] = 1
      else if (noise < 0.75) terrain[row][col] = 2
      else terrain[row][col] = 3
    }
  }

  departments.forEach(department => {
    for (let rowOffset = -2; rowOffset <= 2; rowOffset += 1) {
      for (let colOffset = -3; colOffset <= 3; colOffset += 1) {
        const row = department.row + rowOffset
        const col = department.col + colOffset

        if (
          row >= 0 &&
          row < MAP_ROWS &&
          col >= 0 &&
          col < MAP_COLS &&
          Math.abs(rowOffset) + Math.abs(colOffset) < 5
        ) {
          terrain[row][col] = 1
        }
      }
    }
  })

  return terrain
}

function generateWall() {
  const centerX = MAP_COLS / 2
  const centerY = MAP_ROWS / 2
  const segments = 64
  const points = []

  for (let index = 0; index < segments; index += 1) {
    const angle = (index / segments) * Math.PI * 2
    const baseRadius = 10 + hash(index * 3, 42) * 3
    const radius =
      baseRadius +
      Math.sin(angle * 3 + 0.5) * 2 +
      Math.cos(angle * 5 + 1.2) * 1.5

    points.push({
      x: centerX + Math.cos(angle) * radius,
      y: centerY + Math.sin(angle) * radius,
    })
  }

  return points
}

function isInsideWall(wallPoints, col, row) {
  let inside = false

  for (let index = 0, previous = wallPoints.length - 1; index < wallPoints.length; previous = index++) {
    const currentX = wallPoints[index].x
    const currentY = wallPoints[index].y
    const previousX = wallPoints[previous].x
    const previousY = wallPoints[previous].y

    if (
      (currentY > row) !== (previousY > row) &&
      col < ((previousX - currentX) * (row - currentY)) / (previousY - currentY) + currentX
    ) {
      inside = !inside
    }
  }

  return inside
}

function generatePaths(departments) {
  const paths = new Set()

  function makePath(origin, target) {
    let col = origin.col
    let row = origin.row

    while (col !== target.col || row !== target.row) {
      paths.add(`${col},${row}`)

      if (Math.abs(target.col - col) > Math.abs(target.row - row)) {
        col += target.col > col ? 1 : -1
      } else {
        row += target.row > row ? 1 : -1
      }
    }
  }

  for (let index = 0; index < departments.length; index += 1) {
    const nextIndex = (index + 1) % departments.length
    makePath(departments[index], departments[nextIndex])
  }

  return paths
}

function placeLemmings(departments) {
  const sprites = []

  departments.forEach(department => {
    const lemmings = department.lemmings || []

    lemmings.forEach((lemming, index) => {
      const angle = (index / Math.max(lemmings.length, 1)) * Math.PI * 2 + hash(index, department.col) * 1.2
      const distance = 3 + hash(index + 7, department.row + 3) * 3
      const col = Math.round(department.col + Math.cos(angle) * distance)
      const row = Math.round(department.row + Math.sin(angle) * distance)

      sprites.push({
        ...lemming,
        col: Math.max(2, Math.min(MAP_COLS - 3, col)),
        row: Math.max(2, Math.min(MAP_ROWS - 3, row)),
        deptColor: department.color,
        deptName: department.name,
        deptId: department.id,
        wanderX: 0,
        wanderY: 0,
        wanderPhase: Math.random() * Math.PI * 2,
        wanderSpeed: 0.005 + Math.random() * 0.01,
      })
    })
  })

  return sprites
}

function createMessages(paths, departments) {
  const pathPoints = [...paths].map(point => {
    const [x, y] = point.split(",").map(Number)
    return {x, y}
  })

  if (pathPoints.length === 0) {
    return {pathPoints, messages: []}
  }

  const messageCount = Math.min(6, Math.max(2, departments.length * 2))
  const messages = []

  for (let index = 0; index < messageCount; index += 1) {
    messages.push({
      idx: Math.floor(Math.random() * pathPoints.length),
      progress: 0,
      speed: 0.015 + Math.random() * 0.025,
      color: departments[index % departments.length]?.color || "#3ddc84",
    })
  }

  return {pathPoints, messages}
}

function drawTerrain(ctx, terrain, paths, wallPoints) {
  for (let row = 0; row < MAP_ROWS; row += 1) {
    for (let col = 0; col < MAP_COLS; col += 1) {
      const inside = isInsideWall(wallPoints, col, row)
      const terrainType = terrain[row][col]
      const variation = (col * 7 + row * 13) % 2

      ctx.fillStyle = inside ? TERRAIN_COLORS[terrainType][variation] : "#060d06"
      ctx.fillRect(col * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE)

      if (!inside) {
        continue
      }

      if (terrainType <= 1 && hash(col + 5, row + 3) > 0.7) {
        ctx.fillStyle = "rgba(61,220,132,0.04)"
        ctx.fillRect(col * TILE_SIZE + 4, row * TILE_SIZE + 8, 2, 4)
        ctx.fillRect(col * TILE_SIZE + 10, row * TILE_SIZE + 6, 2, 5)
      }

      if (terrainType === 3 && hash(col + 2, row + 7) > 0.5) {
        ctx.fillStyle = "#1e2e22"
        ctx.fillRect(col * TILE_SIZE + 6, row * TILE_SIZE + 10, 4, 3)
      }

      if (paths.has(`${col},${row}`)) {
        ctx.fillStyle = "rgba(61,220,132,0.08)"
        ctx.fillRect(col * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE)

        if ((col + row) % 3 === 0) {
          ctx.fillStyle = "rgba(61,220,132,0.15)"
          ctx.fillRect(col * TILE_SIZE + 8, row * TILE_SIZE + 8, 3, 3)
        }
      }
    }
  }
}

function drawWall(ctx, wallPoints, cityColor) {
  ctx.strokeStyle = cityColor
  ctx.lineWidth = 3
  ctx.globalAlpha = 0.25
  ctx.beginPath()
  ctx.moveTo(wallPoints[0].x * TILE_SIZE, wallPoints[0].y * TILE_SIZE)

  for (let index = 1; index <= wallPoints.length; index += 1) {
    const point = wallPoints[index % wallPoints.length]
    ctx.lineTo(point.x * TILE_SIZE, point.y * TILE_SIZE)
  }

  ctx.closePath()
  ctx.stroke()

  ctx.lineWidth = 8
  ctx.globalAlpha = 0.04
  ctx.stroke()
  ctx.globalAlpha = 1
}

function drawOutsideFog(ctx, wallPoints) {
  for (let row = 0; row < MAP_ROWS; row += 1) {
    for (let col = 0; col < MAP_COLS; col += 1) {
      if (isInsideWall(wallPoints, col, row)) {
        continue
      }

      let minDistance = 999

      for (let index = 0; index < wallPoints.length; index += 4) {
        const dx = col - wallPoints[index].x
        const dy = row - wallPoints[index].y
        minDistance = Math.min(minDistance, Math.sqrt(dx * dx + dy * dy))
      }

      ctx.fillStyle = `rgba(4,8,4,${Math.min(1, 0.5 + minDistance * 0.06)})`
      ctx.fillRect(col * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE)
    }
  }
}

function drawMessages(ctx, pathPoints, messages) {
  messages.forEach(message => {
    message.progress += message.speed

    if (message.progress >= 1) {
      message.progress = 0
      message.idx = (message.idx + 1) % pathPoints.length
    }

    const current = pathPoints[message.idx]
    const next = pathPoints[(message.idx + 1) % pathPoints.length]
    const pixelX = (current.x + (next.x - current.x) * message.progress) * TILE_SIZE + TILE_SIZE / 2
    const pixelY = (current.y + (next.y - current.y) * message.progress) * TILE_SIZE + TILE_SIZE / 2

    ctx.fillStyle = message.color
    ctx.globalAlpha = 0.5
    ctx.fillRect(pixelX - 1, pixelY - 1, 3, 3)
    ctx.globalAlpha = 1
  })
}

function drawDepartment(ctx, department, tick) {
  const pixelX = department.col * TILE_SIZE
  const pixelY = department.row * TILE_SIZE

  ctx.fillStyle = department.color
  ctx.globalAlpha = 0.05 + Math.sin(tick * 0.03) * 0.02
  ctx.fillRect(pixelX - 24, pixelY - 24, TILE_SIZE + 48, TILE_SIZE + 48)
  ctx.globalAlpha = 1

  ctx.fillStyle = "#0c1a10"
  ctx.fillRect(pixelX - 14, pixelY - 8, TILE_SIZE + 28, TILE_SIZE + 16)
  ctx.strokeStyle = department.color
  ctx.lineWidth = 1
  ctx.strokeRect(pixelX - 14, pixelY - 8, TILE_SIZE + 28, TILE_SIZE + 16)

  const buildingHeight = 22
  ctx.fillStyle = "#0a1610"
  ctx.fillRect(pixelX - 6, pixelY - 8 - buildingHeight, 16, buildingHeight)
  ctx.strokeRect(pixelX - 6, pixelY - 8 - buildingHeight, 16, buildingHeight)
  ctx.fillRect(pixelX + 12, pixelY - 8 - 12, 8, 12)
  ctx.strokeRect(pixelX + 12, pixelY - 8 - 12, 8, 12)

  for (let windowY = pixelY - 8 - buildingHeight + 4; windowY < pixelY - 10; windowY += 6) {
    for (let windowX = pixelX - 3; windowX < pixelX + 8; windowX += 5) {
      const lit = Math.sin(tick * 0.06 + windowX * 0.3 + windowY * 0.2) > 0
      ctx.fillStyle = lit ? department.color : "#0a1610"
      ctx.globalAlpha = lit ? 0.5 : 1
      ctx.fillRect(windowX, windowY, 2, 2)
    }
  }

  ctx.globalAlpha = 1

  const wingLit = Math.sin(tick * 0.07 + department.col) > -0.2
  ctx.fillStyle = wingLit ? department.color : "#0a1610"
  ctx.globalAlpha = wingLit ? 0.4 : 1
  ctx.fillRect(pixelX + 14, pixelY - 8 - 8, 2, 2)
  ctx.globalAlpha = 1

  ctx.fillStyle = department.color
  ctx.fillRect(pixelX + 1, pixelY - 8 - buildingHeight - 6, 1, 6)
  ctx.fillRect(pixelX + 2, pixelY - 8 - buildingHeight - 6, 4, 3)
  ctx.globalAlpha = 0.5
  ctx.fillRect(pixelX + 2, pixelY - 8 - buildingHeight - 3, 4, 1)
  ctx.globalAlpha = 1

  ctx.font = '9px "Courier New", monospace'
  ctx.textAlign = "center"
  ctx.fillStyle = department.color
  ctx.fillText(department.name.toUpperCase(), pixelX + TILE_SIZE / 2, pixelY + TILE_SIZE + 18)
  ctx.fillStyle = "#4a7a5a"
  ctx.font = '8px "Courier New", monospace'
  ctx.fillText(`${(department.lemmings || []).length} lemmings`, pixelX + TILE_SIZE / 2, pixelY + TILE_SIZE + 28)
  ctx.textAlign = "left"
}

function drawLemmings(ctx, sprites, tick) {
  sprites.forEach(lemming => {
    lemming.wanderPhase += lemming.wanderSpeed
    lemming.wanderX = Math.sin(lemming.wanderPhase) * 0.8
    lemming.wanderY = Math.cos(lemming.wanderPhase * 0.7 + 1) * 0.6

    const pixelX = (lemming.col + lemming.wanderX) * TILE_SIZE
    const pixelY = (lemming.row + lemming.wanderY) * TILE_SIZE
    const running = lemming.status === "running"

    ctx.fillStyle = "rgba(0,0,0,0.2)"
    ctx.fillRect(pixelX + 2, pixelY + 10, 8, 2)

    ctx.fillStyle = running ? lemming.deptColor : "#2a3a2e"
    ctx.globalAlpha = running ? 0.8 : 0.4
    ctx.fillRect(pixelX + 2, pixelY + 2, 8, 8)
    ctx.fillRect(pixelX + 3, pixelY, 6, 3)

    ctx.fillStyle = "#0a1610"
    ctx.globalAlpha = 1
    ctx.fillRect(pixelX + 4, pixelY + 1, 1, 1)
    ctx.fillRect(pixelX + 7, pixelY + 1, 1, 1)

    if (running) {
      const blink = Math.sin(tick * 0.1 + lemming.wanderPhase) > 0.5

      if (blink) {
        ctx.fillStyle = lemming.deptColor
        ctx.globalAlpha = 0.6
        ctx.fillRect(pixelX + 9, pixelY - 2, 2, 2)
        ctx.globalAlpha = 1
      }
    }

    ctx.font = '7px "Courier New", monospace'
    ctx.textAlign = "center"
    ctx.fillStyle = running ? lemming.deptColor : "#3a5a4a"
    ctx.globalAlpha = 0.6
    ctx.fillText(lemming.name.split(" ")[0], pixelX + 6, pixelY + 20)
    ctx.globalAlpha = 1
    ctx.textAlign = "left"
  })
}

function getHovered(mapX, mapY, departments, lemmingSprites) {
  const hoveredCol = Math.floor(mapX / TILE_SIZE)
  const hoveredRow = Math.floor(mapY / TILE_SIZE)

  for (const lemming of lemmingSprites) {
    const lemmingCol = lemming.col + lemming.wanderX
    const lemmingRow = lemming.row + lemming.wanderY

    if (Math.abs(lemmingCol - hoveredCol) <= 1 && Math.abs(lemmingRow - hoveredRow) <= 1) {
      return {type: "lemming", data: lemming}
    }
  }

  for (const department of departments) {
    if (Math.abs(department.col - hoveredCol) <= 2 && Math.abs(department.row - hoveredRow) <= 2) {
      return {type: "dept", data: department}
    }
  }

  return null
}

function parseCity(data) {
  try {
    const city = JSON.parse(data || "{}")
    return city && typeof city === "object" ? city : {}
  } catch (_error) {
    return {}
  }
}

function parseDepartments(data) {
  try {
    const departments = JSON.parse(data || "[]")
    return Array.isArray(departments) ? departments : []
  } catch (_error) {
    return []
  }
}

function pointerPosition(event, root, canvas, worldWidth, worldHeight) {
  const rootRect = root.getBoundingClientRect()
  const canvasRect = canvas.getBoundingClientRect()
  const cssX = event.clientX - canvasRect.left
  const cssY = event.clientY - canvasRect.top
  const scaleX = worldWidth / canvasRect.width
  const scaleY = worldHeight / canvasRect.height

  return {
    cssX,
    cssY,
    mapX: cssX * scaleX,
    mapY: cssY * scaleY,
    rootRect,
  }
}

function setupCityMap(hook) {
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

  const city = parseCity(root.dataset.city)
  const departments = autoPlaceDepartments(parseDepartments(root.dataset.departments))
  const terrain = generateTerrain(departments)
  const wallPoints = generateWall()
  const paths = generatePaths(departments)
  const lemmingSprites = placeLemmings(departments)
  const {pathPoints, messages} = createMessages(paths, departments)

  let tick = 0
  let frameId = null

  const render = () => {
    ctx.clearRect(0, 0, worldWidth, worldHeight)
    drawTerrain(ctx, terrain, paths, wallPoints)
    drawWall(ctx, wallPoints, city.color || "#61e0ff")
    drawOutsideFog(ctx, wallPoints)
    drawMessages(ctx, pathPoints, messages)
    departments.forEach(department => drawDepartment(ctx, department, tick))
    drawLemmings(ctx, lemmingSprites, tick)
    tick += 1
    frameId = window.requestAnimationFrame(render)
  }

  const hideTooltip = () => {
    tooltip.hidden = true
    root.style.cursor = "default"
  }

  const showTooltip = event => {
    const {cssX, cssY, mapX, mapY, rootRect} = pointerPosition(
      event,
      root,
      canvas,
      worldWidth,
      worldHeight
    )
    const hit = getHovered(mapX, mapY, departments, lemmingSprites)

    if (!hit) {
      hideTooltip()
      return
    }

    tooltip.hidden = false
    tooltip.style.left = `${Math.max(0, Math.min(cssX + 14, rootRect.width - TOOLTIP_WIDTH))}px`
    tooltip.style.top = `${Math.max(0, Math.min(cssY + 14, rootRect.height - TOOLTIP_HEIGHT))}px`

    if (hit.type === "dept") {
      const department = hit.data
      const runningCount = (department.lemmings || []).filter(lemming => lemming.status === "running").length

      tooltip.innerHTML =
        `<b style="color:${department.color}">◆ ${department.name}</b><br>` +
        "<small>Department</small><br>" +
        `Lemmings: ${(department.lemmings || []).length}<br>` +
        `Running: <span style="color:#3ddc84">${runningCount}</span>`
    } else {
      const lemming = hit.data
      const status =
        lemming.status === "running"
          ? '<span style="color:#3ddc84">● running</span>'
          : '<span style="color:#5a8a6a">○ idle</span>'

      tooltip.innerHTML =
        `<b style="color:${lemming.deptColor}">▸ ${lemming.name}</b><br>` +
        `<small>${lemming.deptName}</small><br>` +
        status
    }

    root.style.cursor = "pointer"
  }

  const handleClick = event => {
    const {mapX, mapY} = pointerPosition(event, root, canvas, worldWidth, worldHeight)
    const hit = getHovered(mapX, mapY, departments, lemmingSprites)

    if (hit?.type === "dept") {
      hook.pushEvent("navigate_department", {department_id: hit.data.id})
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

export const CityMapHook = {
  mounted() {
    this._cleanup = setupCityMap(this)
  },

  updated() {
    if (this._cleanup) {
      this._cleanup()
    }

    this._cleanup = setupCityMap(this)
  },

  destroyed() {
    if (this._cleanup) {
      this._cleanup()
    }
  },
}
