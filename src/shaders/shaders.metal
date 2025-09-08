#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float4 position [[position]];
  float4 color;
  float2 uv;
};

struct VertexInput {
  float3 position [[attribute(0)]];
  float4 color [[attribute(1)]];
  float2 uv [[attribute(2)]];
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
  return out;
}

fragment float4 basic_fragment(VertexData data [[stage_in]],
                               constant Uniforms &uniforms [[buffer(0)]],
                               texture2d<float> diffuse_texture [[texture(0)]],
                               sampler texture_sampler [[sampler(0)]]) {
  float4 texture_color = diffuse_texture.sample(texture_sampler, data.uv);
  return texture_color * data.color;
}
