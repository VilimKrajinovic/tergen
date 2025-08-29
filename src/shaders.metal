struct VertexData{
  float4 position [[position]];
  float4 color;
};

vertex VertexData basic_vertex(
    unsigned int vertex_id [[vertex_id]]
    ){
  float2 vertices [] = {
    {0.5, 0.5},
    {0.5, -0.5},
    {-0.5, 0.5},
    {-0.5, -0.5},
  };

  float3 colors[] = {
    {0.8, 0.2, 0.2},
    {0.2, 0.8, 0.2}
  };


  float2 v = vertices[vertex_id];
  float3 c = colors[vertex_id/2];

  VertexData out;

  out.position = float4(v,0,1);
  out.color = float4(c, 1);

  return out;
}


fragment float4 basic_fragment(
    VertexData data [[stage_in]]
    ){
  return data.color;
}
