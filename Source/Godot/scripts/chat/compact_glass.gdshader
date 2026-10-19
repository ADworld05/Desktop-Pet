shader_type canvas_item;
uniform float opacity=0.72;
uniform float tint=0.3;
uniform float frost=0.75;
uniform vec2 dimensions=vec2(330.0,100.0);
void fragment(){
    vec2 p=UV*dimensions;
    vec2 q=abs(p-dimensions*0.5)-(dimensions*0.5-vec2(18.0));
    float dist=length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-18.0;
    float mask=1.0-smoothstep(-0.8,0.8,dist);
    float rim=(1.0-smoothstep(0.0,1.6,abs(dist)))*0.45;
    float shine=0.10*exp(-UV.y*7.0)+0.04*exp(-length(UV-vec2(0.12,0.06))*5.0);
    float grain=(fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453)-0.5)*0.009*frost;
    vec3 base=mix(vec3(0.96,0.975,0.99),vec3(0.78,0.88,1.0),tint);
    COLOR=vec4(base+shine+rim+grain,clamp(0.12+opacity*0.40+0.03*frost+shine*0.25+rim,0.0,0.99)*mask);
}
