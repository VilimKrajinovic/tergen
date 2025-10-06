#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float4 position [[position]];
  float4 color;
  float2 uv;
  float3 normal;
};

struct VertexInput {
  float3 position [[attribute(0)]];
  float4 color [[attribute(1)]];
  float2 uv [[attribute(2)]];
  float3 normal [[attribute(3)]];
};

struct Uniforms {
  float4x4 mvp;
  float time;
};

vertex VertexData basic_vertex(VertexInput v_in [[stage_in]],
                               constant Uniforms &uniforms [[buffer(0)]]) {
  VertexData out;
  float3 position = v_in.position;

  out.position = float4(position, 1);
  out.color = v_in.color;

  out.position = uniforms.mvp * out.position;
  out.uv = v_in.uv;
  out.normal = v_in.normal;
  return out;
}

fragment float4 basic_fragment(VertexData data [[stage_in]],
                               constant Uniforms &uniforms [[buffer(0)]],
                               texture2d<float> diffuse_texture [[texture(0)]],
                               sampler texture_sampler [[sampler(0)]]) {
  float3 light_dir = normalize(float3(0.5, 1.0, 0.3));
  float3 normal = normalize(data.normal);
  float lighting = max(dot(normal, light_dir), 0.2);

  float4 texture_color = diffuse_texture.sample(texture_sampler, data.uv);
  return data.color * lighting;
}
