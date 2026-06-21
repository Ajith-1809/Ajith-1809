# 3D Scrolling Animated Portfolio Website - Design Specification

**Date**: 2026-05-19  
**Status**: Approved  
**Scope**: Full MVP excluding hosting section

---

## 1. Project Overview

A high-quality, interactive 3D portfolio website built with React and Three.js. The site presents a scroll-driven narrative experience where the user navigates through different sections (Intro, Projects, About, Contact) in an immersive 3D environment.

**Key Characteristics**:
- Smooth scroll-driven camera animation
- Cyberpunk/neon visual aesthetic with dark backgrounds and glowing accents
- Interactive 3D project gallery with hover/click interactions
- Accessibility-first approach with fallbacks
- Performance-optimized for 60 FPS on desktop, 30-45 FPS on mobile

---

## 2. Technical Architecture

### Stack
- **Frontend**: React 18+ with Vite
- **3D Rendering**: React Three Fiber + @react-three/drei
- **Animation**: GSAP + ScrollTrigger
- **Scroll**: Lenis (smooth inertial)
- **State**: Zustand
- **Styling**: Tailwind CSS (or CSS Modules)
- **Postprocessing**: @react-three/postprocessing (bloom)

### Layered Architecture

```
React Application
├── Router (React Router with hash routing)
├── Layout (HTML scaffold, canvas container, UI overlay)
├── ScrollController (Lenis + normalized progress)
└── State Store (Zustand)

UI Layer (DOM elements)
├── Navigation (Bottom overlay capsule)
├── Overlay text (titles, descriptions)
├── Project Details panel
└── Contact Form

Three.js Canvas (@react-three/fiber)
├── Scene Manager (composes Intro, Projects, About, Contact scenes)
├── Camera Rig (scroll-driven positioning)
├── Lighting (ambient, point lights with neon colors)
├── Postprocessing (bloom pass)
└── Interaction System (raycasting)

Asset Layer
├── GLTF models (optional custom 3D elements)
├── Textures (images for project cards)
├── HDR environment (for reflections)
└── Shader Materials (custom effects)
```

---

## 3. Visual Design System

### Color Palette (Cyberpunk Theme)
- **Background**: `#0a0a0f` (deep near-black)
- **Primary Neon (Cyan)**: `#00ffff`
- **Secondary Neon (Magenta)**: `#ff00ff`
- **Accent (Electric Blue)**: `#0088ff`
- **Text (Primary)**: `#ffffff`
- **Text (Secondary)**: `#cccccc`
- **Glass Panel**: `rgba(255, 255, 255, 0.05)` with 1px `rgba(0, 255, 255, 0.2)` border

### Typography
- Headings: Inter or Roboto, weight 700
- Body: Inter, weight 400
- Scale with `clamp()` for responsive sizing
- Monospace for code tags (Fira Code optional)

### Effects
- **Bloom**: threshold ~0.2, strength ~1.5, radius ~0.5 (emissive materials glow)
- **Chromatic Aberration**: subtle, only on hover (radius ~0.003)
- **Glassmorphism**: blur(10px), noise overlay for texture
- **Neon Glow**: CSS `box-shadow` and Three.js `emissive` with intensity

---

## 4. Scene Designs

### 4.1 Intro Scene
**Purpose**: Cinematic entrance that establishes the cyberpunk aesthetic.

**Elements**:
- Particle system (5,000+ particles) swirling in a vortex pattern
  - Colors: cyan and magenta particles, size variance 0.02-0.08
  - Animated with custom shader or CPU (instanced mesh)
- Volumetric fog: `THREE.FogExp2` density 0.02, color dark blue
- Floating logo: 3D geometry (cube or custom shape) with emissive cyan material, slowly rotating
- Cinematic camera path: uses `CatmullRomCurve3` through key-frame points
  - Initial: close-up on logo, dramatic angle
  - Scroll-driven: moves backward and upward, transitioning to gallery view

**Camera Control**:
- First 2 seconds play automatically (no user scroll)
- After that: scroll position (0-0.2 normalized) drives camera along path

### 4.2 Projects Gallery
**Layout**: Circular carousel (radius 8-10 units) around camera center

**Structure**:
- 8 project cards evenly spaced around the circle (45° intervals)
- Camera at origin; lookAt rotates around circle as scroll progresses
- Cards: rectangular glass panels, 2:1 aspect ratio (width:height), size ~3x1.5 units

**Card Content** (Rendered as texture sprites or HTML overlay):
- Preview image (gradient placeholder or actual screenshot)
- Title (large, emissive text)
- Short description (smaller)
- Tech tags (mini pills)

**Interactions**:
- **Hover**: 
  - Raycaster detects pointer over card
  - Target card scales to 1.05x, increases emissive intensity
  - Cursor: pointer (via CSS over canvas)
  - Sound effect optional
- **Click**:
  - Scroll animates camera to focus on selected card (using GSAP)
  - Detail panel slides up from bottom (DOM overlay) with:
    - Larger image
    - Full description
    - Links (GitHub, Live Demo)
    - Close button
  - URL hash updates to `#projects/<id>`

**Scroll Behavior**:
- Overall progress (0.2-0.6) rotates camera from one card to next
- Once selected, camera tracks that card until close; detail panel appears

### 4.3 About Scene
**Layout**: Free-floating elements around a central viewing area

**Elements**:
- **Skill Network**: ~20 floating orbs (spheres) representing skills (React, Three.js, Node, etc.)
  - Orbs are positioned in cloud formation
  - Connected by faint glowing lines (TubeGeometry or LineSegments)
  - On hover: orb expands, shows tooltip with proficiency level
- **Timeline**: A curved path (Bezier) through the scene with milestones placed along it
  - Each milestone: card with date, event title, brief description
  - Timeline line is glowing cyan
- **Mouse Parallax**: Scene group slightly rotates/offsets based on `mousemove` (factor 0.02)

**Transitions**:
- Scroll from Projects (0.6) to About (0.8) fades out projects, fades in about elements

### 4.4 Contact Scene
**Elements**:
- **3D Buttons**: Floating capsules or spheres for:
  - Email (envelope icon)
  - GitHub (logo)
  - LinkedIn (logo)
  - Buttons have emissive material; glow pulses on hover
  - Click opens external link in new tab
- **Holographic Panel**: Semi-transparent grid plane (opacity 0.3) with contact form
  - Form contains: Name (input), Email (input), Message (textarea), Submit button
  - Styled with neon borders and glow on focus
  - **Functionality**: Submit logs to console and shows success animation; can be connected to backend later
  - **Fallback**: Standard HTML form with CSS styling (visible even without JS)

**Lighting**: Soft ambient plus point lights in cyan/magenta orbiting the scene

---

## 5. Navigation & Scroll

### Navigation Component (Bottom Overlay)
- Fixed position at bottom center: `left: 50%; transform: translateX(-50%); bottom: 24px`
- Capsule shape: `padding: 12px 32px; border-radius: 999px`
- Background: `rgba(10, 10, 15, 0.9); border: 1px solid rgba(0, 255, 255, 0.3);`
- Backdrop filter: blur(12px)
- Contains circular icon buttons (4) for sections:
  - Home (house icon)
  - Projects (grid icon)
  - About (user icon)
  - Contact (envelope icon)
- Active section icon highlighted with glow (`box-shadow: 0 0 15px #00ffff`)
- Hover: scale 1.05, border brighter

Mobile: moves to bottom edge, slightly smaller, still centered horizontally.

### Scroll Handling
- **Library**: Lenis (v2) with smooth config: `lerp: 0.08`, `smooth: true`
- **Integration**: 
  - Wrap app in `<Lenis>` from `@studio-freight/react-lenis` or hook manually
  - On each scroll frame: compute normalized progress = `scrollY / (docHeight - winHeight)`
  - Pass progress to 3D scene via Zustand store
- **Section Mapping** (normalized scroll ranges):
  - 0.0 - 0.2: Intro
  - 0.2 - 0.6: Projects Gallery
  - 0.6 - 0.8: About
  - 0.8 - 1.0: Contact
- **Camera Animation**: 
  - Use `useFrame` hook in R3F to interpolate camera position/rotation based on store scrollProgress
  - Map scroll to CatmullRom curve parameters (t from 0 to 1)

---

## 6. State Management (Zustand)

Store: `useAppStore`

State:
```javascript
{
  scrollProgress: 0,           // 0-1 normalized
  currentSection: 'intro',     // 'intro' | 'projects' | 'about' | 'contact'
  hoveredProject: null,        // project id or null
  selectedProject: null,       // project id or null (opens detail)
  loadedSections: Set()        // lazy-load tracking
}
```

Actions:
- `setScrollProgress(progress)`
- `setCurrentSection(section)`
- `setHoveredProject(id)`
- `selectProject(project)` - opens detail panel
- `closeProjectDetail()`

Derived:
- Section from scrollProgress (computed, not stored)

---

## 7. Components Breakdown

### 7.1 Three Canvas
**File**: `src/components/canvas/ThreeCanvas.tsx`

Responsibilities:
- Initialize R3F `<Canvas>` with proper DPR and GL settings
- Wrap entire 3D scene
- Handle resize
- Provide fallback content if WebGL unavailable

R3F Config:
```tsx
<Canvas
  dpr={[1, Math.min(1.5, window.devicePixelRatio)]}
  gl={{
    antialias: false,
    powerPreference: 'high-performance',
    alpha: false
  }}
  camera={{ fov: 50, position: [0, 0, 8], near: 0.1, far: 100 }}
  frameloop="always"
>
  <Scene3D />
  <PostProcessing>
    <Bloom luminanceThreshold={0.2} intensity={1.5} radius={0.5} />
  </PostProcessing>
</Canvas>
```

### 7.2 Scene3D
**File**: `src/components/canvas/Scene3D.tsx`

Composes sub-scenes based on `currentSection`:
```tsx
<group>
  <IntroScene visible={currentSection === 'intro'} />
  <ProjectsGallery visible={currentSection === 'projects'} />
  <AboutScene visible={currentSection === 'about'} />
  <ContactScene visible={currentSection === 'contact'} />
</group>

<CameraRig />
<Lights />
```

Each sub-scene is a separate component that registers its own meshes, lights, and animations.

### 7.3 CameraRig
**File**: `src/components/canvas/CameraRig.tsx`

Uses `useFrame` to drive camera based on scrollProgress:
```tsx
const camera = useThree(state => state.camera);
const scrollProgress = useAppStore(state => state.scrollProgress);

useFrame(() => {
  const t = scrollProgress;
  const position = new THREE.Vector3().lerpVectors(introPos, projectsPos, t);
  camera.position.copy(position);
  // lookAt logic depending on scene
});
```

### 7.4 ProjectsGallery
**File**: `src/components/projects/ProjectsGallery.tsx`

Arranges project cards in circle:
```tsx
const radius = 10;
const count = 8;
cards.forEach((project, i) => {
  const angle = (i / count) * Math.PI * 2;
  const x = Math.sin(angle) * radius;
  const z = Math.cos(angle) * radius;
  return (
    <ProjectCard
      key={project.id}
      project={project}
      position={[x, 0, z]}
      rotation={[0, -angle, 0]} // face center
    />
  );
})
```

Raycasting for hover: Drei's `<Html>` or custom raycaster in useFrame. Handle click via `onPointerDown`.

### 7.5 ProjectCard (3D)
**File**: `src/components/projects/ProjectCard3D.tsx`

Renders a glass panel with content. Material: `MeshPhysicalMaterial` with transmission (glass-like), roughness 0.1, metalness 0.1. Emissive on hover.

Hover state handled via `onPointerOver`, `onPointerOut` that update store.

### 7.6 ProjectDetails (UI Overlay)
**File**: `src/components/projects/ProjectDetails.tsx`

DOM overlay panel that slides from bottom when `selectedProject` is set. Contains title, description, image, links, close button.

### 7.7 UIOverlay
**File**: `src/components/ui/UIOverlay.tsx`

Contains:
- Bottom navigation (capsule)
- Section titles (introductions that fade in/out)
- Loader (splash screen while assets load)

### 7.8 Hooks
- `useScrollProgress()`: returns normalized progress from Lenis scroll
- `useParallax()`: for About scene mouse movement effect
- `useGPUPerf()`: detect device capability, set DPR, toggle effects

---

## 8. Performance Optimization

### Rendering Budget
- Target: 60 FPS on desktop, 30-45 FPS on mobile
- Use `stats.js` in dev only

### Techniques
1. **Instanced Mesh**: Particles use `InstancedMesh` with `BufferGeometry`
2. **Compressed Textures**: Use KTX2/Basis Universal for project images
3. **LOD**: Simple: on mobile, reduce particle count by 75%, lower DPR to 1, disable SSAO
4. **Draw Call Reduction**: Merge geometries where possible; use texture atlases for UI
5. **Postprocessing**: Only bloom enabled; depth-of-field off
6. **Code Splitting**: Lazy load About and Contact scenes using `React.lazy` and `Suspense`
7. **Asset Preloading**: Preload critical assets; show loading screen until ready
8. **Mobile Detection**: Use `navigator.hardwareConcurrency` - if <= 4, apply mobile optimizations

### Adaptive Settings
Store provides derived:
```javascript
const isLowEnd = deviceScore < 5;
const enableBloom = !isLowEnd;
const particleCount = isLowEnd ? 2000 : 5000;
const targetFPS = isLowEnd ? 30 : 60;
```

---

## 9. Accessibility

### Keyboard Navigation
- Make 3D cards focusable via `tabIndex={0}` on wrapper `<div>` (not the canvas itself)
- Listen for `keydown` on window to handle arrow navigation through carousel items
- `Enter` or `Space` triggers click on focused card
- `Escape` closes detail panel

### ARIA
- Buttons in nav have `aria-label="Navigate to Projects section"`
- Project cards have `aria-label` with title and description
- Form inputs have proper `<label>` elements

### Reduced Motion
- CSS: `@media (prefers-reduced-motion: reduce)`
- Disable GSAP animations, use immediate transitions (duration 0)
- Reduce or eliminate camera motion; static camera with immediate jumps
- Disable parallax, particle animation, and bloom pulsing
- Use `lenis.stop()` or simplify to native scroll (no lerp)

### Fallback Content
- Detect WebGL support; if unavailable, render static HTML/CSS version:
  - Each section is a `<section>` with background gradient
  - Projects shown in a grid (CSS Grid)
  - About as a vertical timeline
  - Contact as a simple form
- Ensure core content readable without JavaScript (content in HTML, JS enhances)

---

## 10. Data & Content

### Projects (8 items)
```javascript
[
  {
    id: 1,
    title: "Neural Network Visualizer",
    description: "Interactive 3D visualization of neural network training in real-time.",
    tech: ["Three.js", "TensorFlow.js", "WebGL"],
    link: "https://github.com/example/nn-viz",
    image: "/assets/projects/nn-viz.jpg"
  },
  // ... 7 more with varied tech and descriptions
]
```

### About
- Bio: 2-3 paragraphs as a fictional senior creative developer
- Skills: array of objects `{ name: "React", level: 95 }` etc.
- Timeline: array `{ year: "2022", title: "Senior Frontend Engineer at TechCorp", description: "Led 3D web experiences" }`

### Contact
- Email: `hello@example.com`
- GitHub: `github.com/username`
- LinkedIn: `linkedin.com/in/username`

---

## 11. Implementation Phases

1. **Setup**
   - Initialize Vite + React project
   - Install dependencies
   - Configure Tailwind (optional)
   - Set up folder structure from plan
   - Create Zustand store

2. **Canvas & Camera**
   - Build `ThreeCanvas` with proper GL config
   - Implement `CameraRig` with scroll-driven interpolation
   - Add basic lights

3. **Scroll System**
   - Integrate Lenis (or native with RAF)
   - Normalize progress
   - Map scroll to camera

4. **Intro Scene**
   - Particle system (instanced mesh or points)
   - Fog
   - Logo geometry
   - Camera path animation

5. **Projects Gallery**
   - Circular layout logic
   - ProjectCard component (glass material)
   - Raycaster for hover/click
   - Detail panel (DOM)

6. **UI Overlay**
   - Bottom navigation capsule
   - Section titles overlay
   - Loader component

7. **About Scene**
   - Skill orbs + connections
   - Timeline path + milestones
   - Parallax mouse effect

8. **Contact Scene**
   - 3D buttons (emissive)
   - Holographic form panel
   - Form handling

9. **State Integration**
   - Connect all scenes to store
   - Implement section detection (hash or scroll thresholds)
   - Navigation click handlers (scrollTo)

10. **Postprocessing**
    - Add Bloom
    - Tune parameters for cyberpunk glow

11. **Performance**
    - Adaptive DPR
    - Mobile optimizations (reduce particles, disable effects)
    - Code splitting & lazy loading

12. **Accessibility**
    - Keyboard nav
    - ARIA labels
    - Reduced motion support
    - Fallback HTML/CSS version

13. **Polish**
    - Fine-tune animations (easing, durations)
    - Add subtle sound effects (optional)
    - Test on devices
    - Optimize bundle size

14. **Documentation**
    - README with setup instructions
    - Comment complex logic
    - Add placeholder content guide

---

## 12. Success Criteria

- ✅ 3D scene renders at 60 FPS on mid-range desktop
- ✅ All sections reachable via scroll and navigation
- ✅ Hover and click interactions feel responsive (< 100ms)
- ✅ Site works on mobile (responsive layout, touch-friendly)
- ✅ Keyboard navigation complete (can use Tab/Enter/Esc)
- ✅ Reduced motion preference respected
- ✅ Fallback content functional without WebGL
- ✅ Neon glow effect visible and aesthetically pleasing
- ✅ Deployable build output < 5 MB gzipped (excluding assets)

---

## 13. Out of Scope (Phase 1)

- Audio-reactive effects
- Physics-based interactions
- WebGPU experiment
- Multiplayer/online features
- CMS integration
- AI-generated transitions

These are marked for future enhancement (V2+).

---

## 14. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Performance drop on mobile due to particle count | High | Medium | Implement adaptive reduction; test early on device |
| Scroll-3D desync on touch devices | Medium | Medium | Test touch scrolling thoroughly; adjust Lenis config |
| Raycaster misses hits on transparent materials | Medium | Low | Use `onPointerOver` on mesh with proper material `transparent: false` for hit area; keep invisible hitbox mesh |
| Bloom too heavy on GPU | Medium | Medium | Disable on low-end devices; tune parameters |
| Keyboard nav feels clunky | Low | Medium | Conduct usability test; adjust focus order |

---

This spec captures all decisions made during the brainstorming phase and provides a clear blueprint for implementation.
