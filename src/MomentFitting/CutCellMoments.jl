
struct CutCellMoments
  data::Vector{Vector{Float64}}
  bgcell_to_cut_cell::Vector{Int32}
end

function CutCellMoments(trian::Triangulation,
                        facet_moments::DomainContribution)
  fi = [ testitem(array) for (trian,array) in facet_moments.dict ]
  li = map(length,fi)
  @assert all(li .== first(li))
  bgmodel = get_background_model(trian)
  Dm = num_dims(bgmodel)
  cell_to_parent_cell = get_glue(trian,Val{Dm}()).tface_to_mface
  data = [ zero(first(fi)) for i in 1:length(cell_to_parent_cell) ]
  bgcell_to_cut_cell = zeros(Int32,num_cells(bgmodel))
  bgcell_to_cut_cell[cell_to_parent_cell] .= 1:length(cell_to_parent_cell)
  CutCellMoments(data,bgcell_to_cut_cell)
end

function MomentFittingMeasures(cut,degree::Int)
  MomentFittingMeasures(cut,cut.geo,degree)
end

function MomentFittingMeasures(cut,in_or_out,degree::Int)
  MomentFittingMeasures(cut,cut.geo,in_or_out,degree)
end

function MomentFittingMeasures(cut,geo::CSG.Geometry,degree::Int)
  MomentFittingMeasures(cut,cut.geo,IN,degree)
end

function MomentFittingMeasures(cut,
                               geo::CSG.Geometry,
                               in_or_out,
                               degree::Int)

  Ωᶜ = Triangulation(cut,CUT,geo)
  Ωⁱ = Triangulation(cut,in_or_out,geo)

  ccell_to_point_vals, ccell_to_weight_vals = #
    compute_lag_moments_from_leg(cut,cut.geo,in_or_out,degree)
  ccell_to_weight_vals = collect(get_array(ccell_to_weight_vals))

  nq = num_cells(Ωᶜ)
  ptrs = collect(1:nq)
  ccell_to_point = Fill(ccell_to_point_vals,nq)
  ccell_to_weight = CompressedArray(ccell_to_weight_vals,ptrs)
  ccell_to_quad = map(1:nq) do i
    GenericQuadrature(ccell_to_point[i],ccell_to_weight[i])
  end

  dΩᶜ = CellQuadrature( #
    ccell_to_quad,ccell_to_point,ccell_to_weight,Ωᶜ,ReferenceDomain())
  dΩⁱ = CellQuadrature(Ωⁱ,degree)
  Measure(dΩᶜ), Measure(dΩⁱ), Measure(lazy_append(dΩᶜ,dΩⁱ))

end

function MomentFittingQuad(active_mesh::Triangulation,
                           cut,
                           degree::Int)
  MomentFittingQuad(active_mesh,cut,cut.geo,degree)
end

function MomentFittingQuad(active_mesh::Triangulation,
                           cut,
                           in_or_out,
                           degree::Int)
  MomentFittingQuad(active_mesh,cut,cut.geo,in_or_out,degree)
end

function MomentFittingQuad(active_mesh::Triangulation,
                           cut,
                           geo::CSG.Geometry,
                           degree::Int)

  MomentFittingQuad(active_mesh,cut,geo,IN,degree)
end

function MomentFittingQuad(active_mesh::Triangulation,
                           cut,
                           geo::CSG.Geometry,
                           in_or_out,
                           degree::Int)

  acell_to_point_vals, acell_to_weight_vals = #
    compute_lag_moments_from_leg(cut,geo,in_or_out,degree)
  acell_to_weight_vals = collect(get_array(acell_to_weight_vals))

  D = num_dims(active_mesh)
  bgcell_to_inoutcut = compute_bgcell_to_inoutcut(cut,geo)
  acell_to_bgcell = get_glue(active_mesh,Val{D}()).tface_to_mface
  acell_to_inoutcut = lazy_map(Reindex(bgcell_to_inoutcut),acell_to_bgcell)
  acell_to_point_ptrs = lazy_map(i->(i == CUT ? 1 : 2),acell_to_inoutcut)

  quad = map(r->Quadrature(get_polytope(r),degree),get_reffes(active_mesh))
  @assert length(quad) == 1
  acell_to_point_vals = [acell_to_point_vals,get_coordinates(quad[1])]

  push!(acell_to_weight_vals,get_weights(quad[1]))

  acell_to_is_cut = findall(lazy_map(i->(i == CUT),acell_to_inoutcut))
  num_quads = length(acell_to_weight_vals)
  acell_to_weight_ptrs = map(acell_to_inoutcut) do i
    i == in_or_out ? num_quads : 0
  end
  acell_to_weight_ptrs[acell_to_is_cut] .= 1:length(acell_to_is_cut)

  acell_to_point = CompressedArray(acell_to_point_vals,acell_to_point_ptrs)
  acell_to_weight = CompressedArray(acell_to_weight_vals,acell_to_weight_ptrs)
  acell_to_quad = map(1:length(acell_to_point)) do i
    GenericQuadrature(acell_to_point[i],acell_to_weight[i])
  end

  CellQuadrature( #
    acell_to_quad,acell_to_point,acell_to_weight,active_mesh,ReferenceDomain())
end

# function compute_lag_moments(cut::EmbeddedDiscretization{D,T},
#                              deg::Int) where{D,T}
#   t = Triangulation(cut,cut.geo,CUT_IN)
#   b = JacobiPolynomialBasis{D}(T,deg)
#   p = check_and_get_polytope(cut)
#   orders = tfill(deg,Val{D}())
#   nodes, _ = compute_nodes(p,orders)
#   dofs = LagrangianDofBasis(T,nodes)
#   change = evaluate(dofs,b)
#   println(cond(change))
#   rtol = sqrt(eps(real(float(one(eltype(change))))))
#   change = pinv(change,rtol=rtol)
#   l = linear_combination(change,b)
#   v = Fill(l,num_cells(t))
#   dt = CellQuadrature(t,deg*D)
#   x_gp_ref_1d = dt.cell_point
#   cell_map = get_cell_ref_map(t)
#   x_gp_ref = lazy_map(evaluate,cell_map,x_gp_ref_1d)
#   v_gp_ref = lazy_map(evaluate,v,x_gp_ref)
#   cell_Jt = lazy_map(∇,cell_map)
#   cell_Jtx = lazy_map(evaluate,cell_Jt,x_gp_ref_1d)
#   I_v_in_t = lazy_map(IntegrationMap(),v_gp_ref,dt.cell_weight,cell_Jtx)
#   cbgm = DiscreteModel(cut,cut.geo,CUT)
#   moments = [ zero(first(I_v_in_t)) for i in 1:num_cells(cbgm) ]
#   cell_to_bgcell = get_cell_to_bgcell(t)
#   cell_to_parent_cell = get_cell_to_parent_cell(cbgm)
#   bgcell_to_cell = zeros(Int32,num_cells(get_parent_model(cbgm)))
#   bgcell_to_cell[cell_to_parent_cell] .= 1:length(cell_to_parent_cell)
#   for i in 1:num_cells(t)
#     moments[bgcell_to_cell[cell_to_bgcell[i]]] += I_v_in_t[i]
#   end
#   nodes, moments
# end

function Pᵢ(i::Int)
  P = []
  a = (-1)^i
  for k in 0:i
    push!(P,a*binomial(i,k)*binomial(i+k,k)*(-1)^k)
  end
  P
end

function legendreToMonomial1D(n::Int)
  B = zeros(n+1,n+1)
  for i in 1:n+1
    B[i,1:i] = sqrt(2*i-1)*Pᵢ(i-1)
  end
  B
end

function legendreToMonomial(n::Int,d::Int)
  nt = ntuple(i->1:(n+1),d)
  cis = CartesianIndices(nt)
  B = zeros(length(cis),length(cis))
  B1D = legendreToMonomial1D(n)
  for (i,ci) in enumerate(cis)
    ti = [ B1D[j,:] for j in Tuple(ci) ]
    B[i,:] = kron(ti[end:-1:1]...)
  end
  B
end

function compute_lag_moments_from_leg(cut,
                                      geo::CSG.Geometry,
                                      in_or_out,
                                      degree::Int)
  cut_trian = Triangulation(cut,CUT,geo)
  T = eltype(eltype(get_node_coordinates(cut_trian)))
  D = num_dims(cut_trian)
  b = MonomialBasis{D}(T,degree)
  mon_contribs = compute_monomial_domain_contribution(cut,geo,in_or_out,b,degree)
  mon_moments = compute_monomial_cut_cell_moments(cut_trian,mon_contribs,b)
  mon_to_leg = Fill(legendreToMonomial(degree,D),num_cells(cut_trian))
  leg_moments = lazy_map(*,mon_to_leg,mon_moments)
  p = JacobiPolynomialBasis{D}(T,degree)
  lag_nodes, lag_to_leg = get_nodes_and_change_of_basis(cut_trian,cut,p,degree)
  lag_moments = lazy_map(*,lag_to_leg,leg_moments)
  lag_nodes, lag_moments
end

# function compute_cell_moments(cut::EmbeddedDiscretization{D,T},
#                               degree::Int) where{D,T}
#   bgtrian = Triangulation(cut.bgmodel)
#   b = MonomialBasis{D}(T,degree)
#   cut_bgmodel = DiscreteModel(cut,cut.geo,CUT)
#   mon_contribs = compute_monomial_domain_contribution(cut,b,degree)
#   mon_moments = compute_monomial_cut_cell_moments(cut_bgmodel,mon_contribs,b)
#   lag_nodes, lag_to_mon = get_nodes_and_change_of_basis(cut_bgmodel,cut,b,degree)
#   lag_moments = lazy_map(*,lag_to_mon,mon_moments)
#   lag_nodes, lag_moments, mon_moments, lag_to_mon
# end

function compute_monomial_domain_contribution(cut,
                                              in_or_out,
                                              b::MonomialBasis,
                                              deg::Int)
  compute_monomial_domain_contribution(cut,cut.geo,in_or_out,b,deg)
end

function cut_facets(cut::EmbeddedDiscretization,geo::CSG.Geometry)
  cut_facets(cut.bgmodel,geo)
end

function compute_monomial_domain_contribution(cut,
                                              geo::CSG.Geometry,
                                              in_or_out::Integer,
                                              b::MonomialBasis,
                                              deg::Int)

  cut_io = CutInOrOut(in_or_out)
  dir_Γᵉ = (-1)^(in_or_out==OUT)
  # Embedded facets
  Γᵉ = EmbeddedBoundary(cut,geo)
  # Interior fitted cut facets
  Λ  = GhostSkeleton(cut)
  cutf = cut_facets(cut,geo)
  Γᶠ = SkeletonTriangulation(Λ,cutf,cut_io,geo)
  # Boundary fitted cut facets
  Γᵒ = BoundaryTriangulation(cutf,cut_io)
  # Interior non-cut facets
  Γᵇ = SkeletonTriangulation(Λ,cutf,in_or_out,geo)
  # Boundary non-cut facets
  Λ  = BoundaryTriangulation(cut.bgmodel)
  Γᵖ = BoundaryTriangulation(Λ,cutf,in_or_out,geo)

  D = num_dims(cut.bgmodel)
  @check num_cells(Γᵉ) > 0
  J = int_c_b(Γᵉ,b,deg*D)*dir_Γᵉ +
      int_c_b(Γᶠ.⁺,b,deg*D) + int_c_b(Γᶠ.⁻,b,deg*D)
  if num_cells(Γᵇ) > 0
    J += int_c_b(Γᵇ.⁺,b,deg) + int_c_b(Γᵇ.⁻,b,deg)
  end
  if num_cells(Γᵒ) > 0
    J += int_c_b(Γᵒ,b,deg*D)
  end
  if num_cells(Γᵖ) > 0
    J += int_c_b(Γᵖ,b,deg)
  end
  J

end

function int_c_b(t::Triangulation,b::MonomialBasis,deg::Int)

  Dm = num_dims(get_background_model(t))
  dt = CellQuadrature(t,deg)
  x_gp_ref_1d = dt.cell_point
  facet_map = get_glue(t,Val{Dm}()).tface_to_mface_map
  x_gp_ref = lazy_map(evaluate,facet_map,x_gp_ref_1d)

  cell_map = get_cell_map(get_background_model(t))
  facet_cell = get_glue(t,Val{Dm}()).tface_to_mface
  facet_cell_map = lazy_map(Reindex(cell_map),facet_cell)
  facet_cell_Jt = lazy_map(∇,facet_cell_map)
  facet_cell_Jtx = lazy_map(evaluate,facet_cell_Jt,x_gp_ref)

  facet_n = get_facet_normal(t)
  facet_nx = lazy_map(evaluate,facet_n,x_gp_ref_1d)
  facet_nx_r = lazy_map(Broadcasting(push_normal),facet_cell_Jtx,facet_nx)
  c = lazy_map(Broadcasting(⋅),facet_nx_r,x_gp_ref)

  v = Fill(b,num_cells(t))
  v_gp_ref = lazy_map(evaluate,v,x_gp_ref)
  c_v = map(Broadcasting(*),v_gp_ref,c)

  facet_Jt = lazy_map(∇,facet_map)
  facet_Jtx = lazy_map(evaluate,facet_Jt,x_gp_ref_1d)

  I_c_v_in_t = lazy_map(IntegrationMap(),c_v,dt.cell_weight,facet_Jtx)

  cont = DomainContribution()
  add_contribution!(cont,t,I_c_v_in_t)
  cont

end

function compute_monomial_cut_cell_moments(model::Triangulation,
                                           facet_moments::DomainContribution,
                                           b::MonomialBasis{D,T}) where {D,T}
  cut_cell_to_moments = CutCellMoments(model,facet_moments)
  for (trian,array) in facet_moments.dict
    add_facet_moments!(cut_cell_to_moments,trian,array)
  end
  o = get_terms_degrees(b)
  q = 1 ./ ( D .+ o )
  [ q .* d for d in cut_cell_to_moments.data ]
end

function add_facet_moments!(ccm::CutCellMoments,trian,array::AbstractArray)
  @abstractmethod
end

function add_facet_moments!(ccm::CutCellMoments,
                            trian::SubFacetTriangulation,
                            array::AbstractArray)
  add_facet_moments!(ccm,trian.subfacets,array)
end

function add_facet_moments!(ccm::CutCellMoments,
                            sfd::SubFacetData,
                            array::AbstractArray)
  facet_to_cut_cell = lazy_map(Reindex(ccm.bgcell_to_cut_cell),sfd.facet_to_bgcell)
  for i = 1:length(facet_to_cut_cell)
    ccm.data[facet_to_cut_cell[i]] += array[i]
  end
end

function add_facet_moments!(ccm::CutCellMoments,
                            trian::SubFacetBoundaryTriangulation,
                            array::AbstractArray)
  if length(trian.subfacet_to_facet) > 0
    subfacet_to_bgcell = lazy_map(Reindex(trian.facets.glue.face_to_cell),trian.subfacet_to_facet)
    subfacet_to_cut_cell = lazy_map(Reindex(ccm.bgcell_to_cut_cell),subfacet_to_bgcell)
    l = length(subfacet_to_cut_cell)
    for i = 1:l
      ccm.data[subfacet_to_cut_cell[i]] += array[i]
    end
  else
    add_facet_moments!(ccm,trian.facets,array)
  end
end

function add_facet_moments!(ccm::CutCellMoments,
                            trian::BoundaryTriangulation,
                            array::AbstractArray)
  add_facet_moments!(ccm,trian.glue,array)
end

function add_facet_moments!(ccm::CutCellMoments,
                            glue::FaceToCellGlue,
                            array::AbstractArray)
  facet_to_cut_cell = lazy_map(Reindex(ccm.bgcell_to_cut_cell),glue.face_to_cell)
  cell_to_is_cut = findall(lazy_map(i->(i>0),facet_to_cut_cell))
  facet_to_cut_cell = lazy_map(Reindex(facet_to_cut_cell),cell_to_is_cut)
  l = length(facet_to_cut_cell)
  for i = 1:l
    ccm.data[facet_to_cut_cell[i]] += array[cell_to_is_cut[i]]
  end
end

function add_facet_moments!(ccm::CutCellMoments,
                            trian::Triangulation,
                            array::AbstractArray)

  Dp = num_point_dims(trian)
  Dc = num_cell_dims(trian)
  @assert Dc == Dp-1
  @assert Dp == num_dims(get_background_model(trian))
  facet_to_bgcell = get_glue(trian,Val(Dp)).tface_to_mface
  facet_to_cut_cell = lazy_map(Reindex(ccm.bgcell_to_cut_cell),facet_to_bgcell)
  l = length(facet_to_cut_cell)
  for i = 1:l
    ccm.data[facet_to_cut_cell[i]] += array[i]
  end
end

function get_nodes_and_change_of_basis(model::Triangulation,
                                       cut,
                                       b,
                                       degree::Int)
  D = num_dims(model)
  T = eltype(eltype(get_node_coordinates(model)))
  p = check_and_get_polytope(cut)
  orders = tfill(degree,Val{D}())
  nodes, _ = compute_nodes(p,orders)
  dofs = LagrangianDofBasis(T,nodes)
  change = evaluate(dofs,b)
  change = transpose(inv(change))
  change = Fill(change,num_cells(model))
  nodes, change
end

function map_to_ref_space!(moments::AbstractArray,
                           nodes::Vector{<:Point},
                           model::Triangulation)
  cell_map = get_cell_map(model)
  cell_Jt = lazy_map(∇,cell_map)
  cell_detJt = lazy_map(Operation(det),cell_Jt)
  cell_nodes = Fill(nodes,num_cells(model))
  detJt = lazy_map(evaluate,cell_detJt,cell_nodes)
  moments = lazy_map(Broadcasting(/),moments,detJt)
end

@inline function check_and_get_polytope(cut)
  _check_and_get_polytope(cut.bgmodel.grid)
end

@inline function get_terms_degrees(b::MonomialBasis)
  [ _get_terms_degrees(c) for c in b.terms ]
end

function _get_terms_degrees(c::CartesianIndex)
  d = 0
  for i in 1:length(c)
    d += (c[i]-1)
  end
  d
end

