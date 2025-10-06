package tergen

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import sdl "vendor:sdl3"

OBJ_Data :: struct {
	vertices: []Vertex_Data,
	indices:  []u32,
}

load_obj :: proc(file_path: string) -> (OBJ_Data, bool) {
	data, ok := os.read_entire_file(file_path)
	if !ok {
		fmt.printf("Failed to read OBJ file: %s\n", file_path)
		return {}, false
	}
	defer delete(data)

	content := string(data)
	lines := strings.split_lines(content)
	defer delete(lines)

	positions: [dynamic]Vec3
	uvs: [dynamic]Vec2
	normals: [dynamic]Vec3

	face_vertices: [dynamic]Vertex_Data
	face_indices: [dynamic]u32
	vertex_map := make(map[string]u32)
	defer delete(vertex_map)

	for line in lines {
		line := strings.trim_space(line)
		if len(line) == 0 || strings.has_prefix(line, "#") {
			continue
		}

		parts := strings.fields(line)
		if len(parts) == 0 {
			continue
		}

		switch parts[0] {
		case "v":
			if len(parts) >= 4 {
				x, x_ok := strconv.parse_f32(parts[1])
				y, y_ok := strconv.parse_f32(parts[2])
				z, z_ok := strconv.parse_f32(parts[3])
				if x_ok && y_ok && z_ok {
					append(&positions, Vec3{x, y, z})
				}
			}

		case "vt":
			if len(parts) >= 3 {
				u, u_ok := strconv.parse_f32(parts[1])
				v, v_ok := strconv.parse_f32(parts[2])
				if u_ok && v_ok {
					append(&uvs, Vec2{u, 1.0 - v}) // Flip V coordinate for OpenGL/Metal
				}
			}

		case "vn":
			if len(parts) >= 4 {
				x, x_ok := strconv.parse_f32(parts[1])
				y, y_ok := strconv.parse_f32(parts[2])
				z, z_ok := strconv.parse_f32(parts[3])
				if x_ok && y_ok && z_ok {
					append(&normals, Vec3{x, y, z})
				}
			}

		case "f":
			if len(parts) >= 4 {
				face_vertex_indices := make([dynamic]u32, 0, len(parts) - 1)
				defer delete(face_vertex_indices)

				for i in 1 ..< len(parts) {
					vertex_str := parts[i]

					if idx, exists := vertex_map[vertex_str]; exists {
						append(&face_vertex_indices, idx)
					} else {
						vertex_parts := strings.split(vertex_str, "/")
						defer delete(vertex_parts)

						pos_idx, uv_idx, norm_idx := -1, -1, -1

						if len(vertex_parts) >= 1 && vertex_parts[0] != "" {
							if idx, ok := strconv.parse_int(vertex_parts[0]); ok {
								pos_idx = int(idx) - 1 // OBJ is 1-indexed
							}
						}
						if len(vertex_parts) >= 2 && vertex_parts[1] != "" {
							if idx, ok := strconv.parse_int(vertex_parts[1]); ok {
								uv_idx = int(idx) - 1
							}
						}
						if len(vertex_parts) >= 3 && vertex_parts[2] != "" {
							if idx, ok := strconv.parse_int(vertex_parts[2]); ok {
								norm_idx = int(idx) - 1
							}
						}

						vertex := Vertex_Data {
							pos    = positions[pos_idx] if pos_idx >= 0 && pos_idx < len(positions) else Vec3{0, 0, 0},
							normal = normals[norm_idx] if norm_idx >= 0 && norm_idx < len(normals) else Vec3{0, 0, 0},
							color  = sdl.FColor{1, 1, 1, 1}, // Default white color
							uv     = uvs[uv_idx] if uv_idx >= 0 && uv_idx < len(uvs) else Vec2{0, 0},
						}

						new_idx := u32(len(face_vertices))
						append(&face_vertices, vertex)
						vertex_map[vertex_str] = new_idx
						append(&face_vertex_indices, new_idx)
					}
				}

				// Triangulate face (assuming convex polygons)
				if len(face_vertex_indices) >= 3 {
					for i in 1 ..< len(face_vertex_indices) - 1 {
						append(&face_indices, face_vertex_indices[0])
						append(&face_indices, face_vertex_indices[i])
						append(&face_indices, face_vertex_indices[i + 1])
					}
				}
			}
		}
	}

	vertices_slice := slice.clone(face_vertices[:])
	indices_slice := slice.clone(face_indices[:])

	return OBJ_Data{vertices = vertices_slice, indices = indices_slice}, true
}

free_obj_data :: proc(data: ^OBJ_Data) {
	delete(data.vertices)
	delete(data.indices)
	data^ = {}
}
