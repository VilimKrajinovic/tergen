#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float4 position [[position]];
  float4 color;
};

struct VeertexInput {
  float3 position [[attribute(0)]];
  float4 color [[attribute(1)]];
};

struct Uniforms {
  float4x4 mvp;
  float time;
};

vertex VertexData basic_vertex(VeertexInput v_in [[stage_in]],
                               constant Uniforms &uniforms [[buffer(0)]]) {
  VertexData out;
  float3 position = v_in.position;

  out.position = float4(position, 1);
  out.color = v_in.color;

  out.position = uniforms.mvp * out.position;
  return out;
}

fragment float4 basic_fragment(VertexData data [[stage_in]],
                               constant Uniforms &uniforms [[buffer(0)]]) {
  return data.color;
}
